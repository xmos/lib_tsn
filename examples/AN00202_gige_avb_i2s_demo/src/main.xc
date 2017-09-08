// Copyright (c) 2014-2017, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <string.h>
#include <xscope.h>
#include "gpio.h"
#include "i2s.h"
#include "i2c.h"
#include "avb.h"
#include "audio_clock_CS2100CP.h"
#include "xassert.h"
#include "debug_print.h"
#include "gptp.h"
#include "aem_descriptor_types.h"
#include "ethernet.h"
#include "smi.h"
#include "audio_buffering.h"
#include "sinewave.h"

// Ports and clocks used by the application
on tile[0]: otp_ports_t otp_ports0 = OTP_PORTS_INITIALIZER; // Ports are hardwired to internal OTP for reading
                                                            // MAC address and serial number
// Fixed QSPI flash ports that are used for firmware upgrade and persistent data storage
on tile[0]: fl_QSPIPorts qspi_ports =
{
  XS1_PORT_1B,
  XS1_PORT_1C,
  XS1_PORT_4B,
  XS1_CLKBLK_1
};

on tile[1]: rgmii_ports_t rgmii_ports = RGMII_PORTS_INITIALIZER; // Fixed RGMII ports on Tile 1
on tile[1]: port p_smi_mdio = XS1_PORT_1C;
on tile[1]: port p_smi_mdc = XS1_PORT_1D;
on tile[1]: port p_eth_reset = XS1_PORT_4A;

on tile[1]: out port p_leds_row = XS1_PORT_4C;
on tile[1]: out port p_leds_column = XS1_PORT_4D;
on tile[0]: port p_i2c = XS1_PORT_4A;

// I2S ports and clocks
on tile[0]: out buffered port:32 p_fs[1] = { XS1_PORT_1A }; // Low frequency PLL frequency reference
on tile[0]: out buffered port:32 p_i2s_lrclk = XS1_PORT_1G;
on tile[0]: out buffered port:32 p_i2s_bclk = XS1_PORT_1H;
on tile[0]: in port p_i2s_mclk = XS1_PORT_1F;
on tile[0]: out buffered port:32 p_aud_dout[4] = {XS1_PORT_1M, XS1_PORT_1N, XS1_PORT_1O, XS1_PORT_1P};
on tile[0]: in buffered port:32 p_aud_din[4] = {XS1_PORT_1I, XS1_PORT_1J, XS1_PORT_1K, XS1_PORT_1L};
on tile[0]: clock clk_i2s_bclk = XS1_CLKBLK_3;
on tile[0]: clock clk_i2s_mclk = XS1_CLKBLK_4;

on tile[0]: out port p_audio_shared = XS1_PORT_8C;

#define CS5368_ADDR           0x4C // I2C address of the CS5368 DAC
#define CS5368_CHIP_REV       0x00 // DAC register addresses...
#define CS5368_GCTL_MDE       0x01
#define CS5368_OVFL_ST        0x02

#define CS4384_ADDR           0x18 // I2C address of the CS4384 ADC
#define CS4384_CHIP_REV       0x01 // ADC register addresses...
#define CS4384_MODE_CTRL      0x02
#define CS4384_PCM_CTRL       0x03
#define CS4384_DSD_CTRL       0x04
#define CS4384_FLT_CTRL       0x05
#define CS4384_INV_CTRL       0x06
#define CS4384_GRP_CTRL       0x07
#define CS4384_RMP_MUTE       0x08
#define CS4384_MUTE_CTRL      0x09
#define CS4384_MIX_PR1        0x0a
#define CS4384_VOL_A1         0x0b
#define CS4384_VOL_B1         0x0c
#define CS4384_MIX_PR2        0x0d
#define CS4384_VOL_A2         0x0e
#define CS4384_VOL_B2         0x0f
#define CS4384_MIX_PR3        0x10
#define CS4384_VOL_A3         0x11
#define CS4384_VOL_B3         0x12
#define CS4384_MIX_PR4        0x13
#define CS4384_VOL_A4         0x14
#define CS4384_VOL_B4         0x15
#define CS4384_CM_MODE        0x16
#define CS5368_CHIP_REV       0x00
#define CS5368_GCTL_MDE       0x01
#define CS5368_OVFL_ST        0x02
#define CS5368_OVFL_MSK       0x03
#define CS5368_HPF_CTRL       0x04
#define CS5368_PWR_DN         0x06
#define CS5368_MUTE_CTRL      0x08
#define CS5368_SDO_EN         0x0a

#pragma unsafe arrays
[[always_inline]][[distributable]]
void buffer_manager_to_i2s(server i2s_callback_if i2s,
                           streaming chanend c_audio,
                           client interface i2c_master_if i2c,
                           streaming chanend c_sound_activity,
                           int synth_sinewave_channel_mask,
                           client output_gpio_if dac_reset,
                           client output_gpio_if adc_reset,
                           client output_gpio_if pll_select,
                           client output_gpio_if mclk_select)
{
  audio_frame_t *unsafe p_in_frame;
  audio_double_buffer_t *unsafe double_buffer;
  int32_t *unsafe sample_out_buf;
  unsigned cur_sample_rate;
  const int sound_activity_threshold = 100000;
  const int sound_activity_update_interval = 2500;
  int sound_activity_update = 0;
  int sinewave_index = 0;
  int channel_mask = 0;
  timer tmr;

  audio_clock_CS2100CP_init(i2c);

  while (1) {
    select {
    case i2s.init(i2s_config_t &?i2s_config, tdm_config_t &?tdm_config):
      // Receive the first free buffer and initial sample rate
      unsafe {
        c_audio :> double_buffer;
        p_in_frame = &double_buffer->buffer[double_buffer->active_buffer];
        c_audio :> cur_sample_rate;
      }
      i2s_config.mode = I2S_MODE_I2S;
      // I2S has 32 bits per sample. *2 as 2 channels
      const unsigned num_bits = 64;
      const unsigned mclk = 512 * 48000;
      // Calculate the MCLK to BCLK ratio using the current sample rate and bits per sample
      i2s_config.mclk_bclk_ratio = mclk / ( cur_sample_rate * num_bits);

      // Set CODEC in reset
      dac_reset.output(0);
      adc_reset.output(0);

      // Select 44.1kHz family clock (22.5792MHz)
      mclk_select.output(0);
      pll_select.output(1);

      // Allow the clock to settle
      delay_milliseconds(2);

      // Take DAC out of reset
      dac_reset.output(1);

      /* Mode Control 1 (Address: 0x02) */
      /* bit[7] : Control Port Enable (CPEN)     : Set to 1 for enable
       * bit[6] : Freeze controls (FREEZE)       : Set to 1 for freeze
       * bit[5] : PCM/DSD Selection (DSD/PCM)    : Set to 0 for PCM
       * bit[4:1] : DAC Pair Disable (DACx_DIS)  : All Dac Pairs enabled
       * bit[0] : Power Down (PDN)               : Powered down
       */
      i2c.write_reg(CS4384_ADDR, CS4384_MODE_CTRL, 0b11000001);

      /* PCM Control (Address: 0x03) */
      /* bit[7:4] : Digital Interface Format (DIF) : 0b1100 for TDM
       * bit[3:2] : Reserved
       * bit[1:0] : Functional Mode (FM) : 0x11 for auto-speed detect (32 to 200kHz)
      */
      i2c.write_reg(CS4384_ADDR, CS4384_PCM_CTRL, 0b00010111);

      /* Mode Control 1 (Address: 0x02) */
      /* bit[7] : Control Port Enable (CPEN)     : Set to 1 for enable
       * bit[6] : Freeze controls (FREEZE)       : Set to 0 for freeze
       * bit[5] : PCM/DSD Selection (DSD/PCM)    : Set to 0 for PCM
       * bit[4:1] : DAC Pair Disable (DACx_DIS)  : All Dac Pairs enabled
       * bit[0] : Power Down (PDN)               : Not powered down
       */
      i2c.write_reg(CS4384_ADDR, CS4384_MODE_CTRL, 0b10000000);

      // Take ADC out of reset
      adc_reset.output(1);

      unsigned adc_dif = 0x01; // I2S mode
      unsigned adc_mode = 0x03;    /* Slave mode all speeds */

      /* Reg 0x01: (GCTL) Global Mode Control Register */
      /* Bit[7]: CP-EN: Manages control-port mode
       * Bit[6]: CLKMODE: Setting puts part in 384x mode
       * Bit[5:4]: MDIV[1:0]: Set to 01 for /2
       * Bit[3:2]: DIF[1:0]: Data Format: 0x01 for I2S, 0x02 for TDM
       * Bit[1:0]: MODE[1:0]: Mode: 0x11 for slave mode
       */
      i2c.write_reg(CS5368_ADDR, CS5368_GCTL_MDE, 0b10010000 | (adc_dif << 2) | adc_mode);

      /* Reg 0x06: (PDN) Power Down Register */
      /* Bit[7:6]: Reserved
       * Bit[5]: PDN-BG: When set, this bit powers-own the bandgap reference
       * Bit[4]: PDM-OSC: Controls power to internal oscillator core
       * Bit[3:0]: PDN: When any bit is set all clocks going to that channel pair are turned off
       */
      i2c.write_reg(CS5368_ADDR, CS5368_PWR_DN, 0b00000000);

      break;

    case i2s.restart_check() -> i2s_restart_t restart:
      unsafe {
        if (sample_out_buf[8]) {
          restart = I2S_RESTART;
          while (!stestct(c_audio)) {
            c_audio :> int;
          }
          sinct(c_audio);
        }
        else {
          restart = I2S_NO_RESTART;
        }
      }
      break; // End of restart check

    case i2s.receive(size_t index, int32_t sample):
      unsafe {
        if (synth_sinewave_channel_mask & (1 << index)) {
          p_in_frame->samples[index] = sinewave[sinewave_index];
        }
        else {
          p_in_frame->samples[index] = sample;
        }
        if (synth_sinewave_channel_mask && index == 0) {
          sinewave_index++;
          if (sinewave_index == 256)
            sinewave_index = 0;
        }
      }
      break;

    case i2s.send(size_t index) -> int32_t sample:
      unsafe {
        if (index == 0) {
          c_audio :> sample_out_buf;
        }
        sample = sample_out_buf[index];
        if ((index & 1) == 0) {
          int32_t stereo_sample_average =
             (sample_out_buf[index] >> 1) + (sample_out_buf[index + 1] >> 1);

          int is_active = (stereo_sample_average > sound_activity_threshold ||
                           stereo_sample_average < -sound_activity_threshold);

          channel_mask |= (is_active << (index >> 1));
        }
        if (index == (AVB_NUM_MEDIA_INPUTS-1)) {
          tmr :> p_in_frame->timestamp;
          audio_frame_t *unsafe new_frame = audio_buffers_swap_active_buffer(*double_buffer);
          c_audio <: p_in_frame;
          p_in_frame = new_frame;
          sound_activity_update++;
          if (sound_activity_update == sound_activity_update_interval) {
            c_sound_activity <: channel_mask;
            soutct(c_sound_activity, XS1_CT_PAUSE);
            sound_activity_update = 0;
            channel_mask = 0;
          }
        }
      }
      break; // End of send
    }
  }
}


[[combinable]]
void ar8035_phy_driver(client interface smi_if smi,
                client interface ethernet_cfg_if eth,
                streaming chanend c_sound_activity) {
  ethernet_link_state_t link_state = ETHERNET_LINK_DOWN;
  ethernet_speed_t link_speed = LINK_1000_MBPS_FULL_DUPLEX;
  const int phy_reset_delay_ms = 1;
  const int link_poll_period_ms = 1000;
  const int phy_address = 0x4;
  timer tmr, tmr2;
  int t, t2;
  int flashing_on = 0;
  int channel_mask = 0;
  tmr :> t;
  p_eth_reset <: 0;
  delay_milliseconds(phy_reset_delay_ms);
  p_eth_reset <: 0xf;
  p_leds_column <: 0x1;

  eth.set_ingress_timestamp_latency(0, LINK_1000_MBPS_FULL_DUPLEX, 200);
  eth.set_egress_timestamp_latency(0, LINK_1000_MBPS_FULL_DUPLEX, 200);

  eth.set_ingress_timestamp_latency(0, LINK_100_MBPS_FULL_DUPLEX, 350);
  eth.set_egress_timestamp_latency(0, LINK_100_MBPS_FULL_DUPLEX, 350);

  while (smi_phy_is_powered_down(smi, phy_address));

  // Disable smartspeed
  smi.write_reg(phy_address, 0x14, 0x80C);
  // Disable hibernation
  smi.write_reg(phy_address, 0x1D, 0xB);
  smi.write_reg(phy_address, 0x1E, 0x3C40);
  // Disable smart EEE
  smi.write_reg(phy_address, 0x0D, 3);
  smi.write_reg(phy_address, 0x0E, 0x805D);
  smi.write_reg(phy_address, 0x0D, 0x4003);
  smi.write_reg(phy_address, 0x0E, 0x1000);
  // Disable EEE auto-neg advertisement
  smi.write_reg(phy_address, 0x0D, 7);
  smi.write_reg(phy_address, 0x0E, 0x3C);
  smi.write_reg(phy_address, 0x0D, 0x4003);
  smi.write_reg(phy_address, 0x0E, 0);

  smi_configure(smi, phy_address, LINK_1000_MBPS_FULL_DUPLEX, SMI_ENABLE_AUTONEG);
  // Periodically check the link status
  while (1) {
    select {
    case tmr when timerafter(t) :> t:
      ethernet_link_state_t new_state = smi_get_link_state(smi, phy_address);
      // Read AR8035 status register bits 15:14 to get the current link speed
      if (new_state == ETHERNET_LINK_UP) {
        link_speed = (ethernet_speed_t)(smi.read_reg(phy_address, 0x11) >> 14) & 3;
      }
      if (new_state != link_state) {
        link_state = new_state;
        eth.set_link_state(0, new_state, link_speed);
      }
      t += link_poll_period_ms * XS1_TIMER_KHZ;
      break;
    case c_sound_activity :> channel_mask:
      break;
    case tmr2 when timerafter(t2) :> void:
      p_leds_row <: ~(flashing_on * channel_mask);
      flashing_on ^= 1;
      t2 += 10000000;
      break;
    }
  }
}

enum mac_rx_lp_clients {
  MAC_TO_MEDIA_CLOCK_PTP = 0,
  MAC_TO_1722_1,
  NUM_ETH_TX_LP_CLIENTS
};

enum mac_tx_lp_clients {
  MEDIA_CLOCK_PTP_TO_MAC = 0,
  AVB1722_1_TO_MAC,
  NUM_ETH_RX_LP_CLIENTS
};

enum mac_cfg_clients {
  MAC_CFG_TO_AVB_MANAGER,
  MAC_CFG_TO_PHY_DRIVER,
  MAC_CFG_TO_MEDIA_CLOCK_PTP,
  MAC_CFG_TO_1722_1,
  NUM_ETH_CFG_CLIENTS
};

enum avb_manager_chans {
  AVB_MANAGER_TO_1722_1,
  AVB_MANAGER_TO_DEMO,
  NUM_AVB_MANAGER_CHANS
};

enum ptp_chans {
  PTP_TO_TALKER,
  PTP_TO_1722_1,
  NUM_PTP_CHANS
};

enum i2c_interfaces {
  I2S_TO_I2C,
  NUM_I2C_IFS
};

enum gpio_shared_audio_pins {
  GPIO_DAC_RST_N = 1,
  GPIO_PLL_SEL = 5,     // 1 = CS2100, 0 = Phaselink clock source
  GPIO_ADC_RST_N = 6,
  GPIO_MCLK_FSEL = 7,   // Select frequency on Phaselink clock. 0 = 22.5792MHz for 44.1k, 1 = 24.576MHz for 48k.
};

static char gpio_pin_map[4] =  {
  GPIO_DAC_RST_N,
  GPIO_ADC_RST_N,
  GPIO_PLL_SEL,
  GPIO_MCLK_FSEL
};

[[combinable]] void application_task(client interface avb_interface avb,
                                     server interface avb_1722_1_control_callbacks i_1722_1_entity);

int main(void)
{
  // Ethernet interfaces and channels
  ethernet_cfg_if i_eth_cfg[NUM_ETH_CFG_CLIENTS];
  ethernet_rx_if i_eth_rx_lp[NUM_ETH_RX_LP_CLIENTS];
  ethernet_tx_if i_eth_tx_lp[NUM_ETH_TX_LP_CLIENTS];
  streaming chan c_eth_rx_hp;
  streaming chan c_eth_tx_hp;
  smi_if i_smi;
  streaming chan c_rgmii_cfg;

  // PTP channels
  chan c_ptp[NUM_PTP_CHANS];

  // AVB unit control
  chan c_talker_ctl[AVB_NUM_TALKER_UNITS];
  chan c_listener_ctl[AVB_NUM_LISTENER_UNITS];
  chan c_buf_ctl[AVB_NUM_LISTENER_UNITS];

  // Media control
  chan c_media_ctl[AVB_NUM_MEDIA_UNITS];
  interface media_clock_if i_media_clock_ctl;

  // Core AVB interface and callbacks
  interface avb_interface i_avb[NUM_AVB_MANAGER_CHANS];
  interface avb_1722_1_control_callbacks i_1722_1_entity;

  // I2C and GPIO interfaces
  i2c_master_if i_i2c[NUM_I2C_IFS];
  interface output_gpio_if i_gpio[4];

  // I2S and audio buffering interfaces
  i2s_callback_if i_i2s;
  streaming chan c_audio;
  interface push_if i_audio_in_push;
  interface pull_if i_audio_in_pull;
  interface push_if i_audio_out_push;
  interface pull_if i_audio_out_pull;
  streaming chan c_sound_activity;

  par
  {
    on tile[1]: rgmii_ethernet_mac(i_eth_rx_lp, NUM_ETH_RX_LP_CLIENTS,
                                   i_eth_tx_lp, NUM_ETH_TX_LP_CLIENTS,
                                   c_eth_rx_hp, c_eth_tx_hp,
                                   c_rgmii_cfg,
                                   rgmii_ports,
                                   ETHERNET_DISABLE_SHAPER);

    on tile[1].core[0]: rgmii_ethernet_mac_config(i_eth_cfg, NUM_ETH_CFG_CLIENTS, c_rgmii_cfg);
    on tile[1].core[0]: ar8035_phy_driver(i_smi, i_eth_cfg[MAC_CFG_TO_PHY_DRIVER], c_sound_activity);

    on tile[1]: [[distribute]] smi(i_smi, p_smi_mdio, p_smi_mdc);

    on tile[0]: gptp_media_clock_server(i_media_clock_ctl,
                                        null,
                                        c_buf_ctl,
                                        AVB_NUM_LISTENER_UNITS,
                                        p_fs,
                                        i_eth_rx_lp[MAC_TO_MEDIA_CLOCK_PTP],
                                        i_eth_tx_lp[MEDIA_CLOCK_PTP_TO_MAC],
                                        i_eth_cfg[MAC_CFG_TO_MEDIA_CLOCK_PTP],
                                        c_ptp, NUM_PTP_CHANS,
                                        PTP_GRANDMASTER_CAPABLE);

    on tile[0]: [[distribute]] i2c_master_single_port(i_i2c, NUM_I2C_IFS, p_i2c, 100, 0, 1, 0);
    on tile[0]: [[distribute]] output_gpio(i_gpio, 4, p_audio_shared, gpio_pin_map);

    on tile[0]: {
      set_core_high_priority_on();
      configure_clock_src(clk_i2s_mclk, p_i2s_mclk);
      start_clock(clk_i2s_mclk);
      i2s_master(i_i2s,
                 p_aud_dout, AVB_NUM_MEDIA_OUTPUTS/2,
                 p_aud_din, AVB_NUM_MEDIA_INPUTS/2,
                 p_i2s_bclk,
                 p_i2s_lrclk,
                 clk_i2s_bclk,
                 clk_i2s_mclk);
    }

    on tile[0]: [[distribute]] buffer_manager_to_i2s(i_i2s, c_audio, i_i2c[I2S_TO_I2C], c_sound_activity, 0xC,
                                                     i_gpio[0], i_gpio[1], i_gpio[2], i_gpio[3]);

    on tile[0]: audio_buffer_manager(c_audio, i_audio_in_push, i_audio_out_pull, c_media_ctl[0], AUDIO_I2S_IO);

    on tile[0]: [[distribute]] audio_input_sample_buffer(i_audio_in_push, i_audio_in_pull);

    on tile[0]: avb_1722_talker(c_ptp[PTP_TO_TALKER],
                                c_eth_tx_hp,
                                c_talker_ctl[0],
                                AVB_NUM_SOURCES,
                                i_audio_in_pull);

    on tile[0]: [[distribute]] audio_output_sample_buffer(i_audio_out_push, i_audio_out_pull);

    on tile[0]: avb_1722_listener(c_eth_rx_hp,
                                  c_buf_ctl[0],
                                  null,
                                  c_listener_ctl[0],
                                  AVB_NUM_SINKS,
                                  i_audio_out_push);

    on tile[0]: {
      char mac_address[6];
      if (otp_board_info_get_mac(otp_ports0, 0, mac_address) == 0) {
        fail("No MAC address programmed in OTP");
      }
      i_eth_cfg[MAC_CFG_TO_AVB_MANAGER].set_macaddr(0, mac_address);
      [[combine]]
      par {
        avb_manager(i_avb, NUM_AVB_MANAGER_CHANS,
                     null,
                     c_media_ctl,
                     c_listener_ctl,
                     c_talker_ctl,
                     i_eth_cfg[MAC_CFG_TO_AVB_MANAGER],
                     i_media_clock_ctl);
        application_task(i_avb[AVB_MANAGER_TO_DEMO], i_1722_1_entity);
        avb_1722_1_maap_srp_task(i_avb[AVB_MANAGER_TO_1722_1],
                                i_1722_1_entity,
                                qspi_ports,
                                i_eth_rx_lp[MAC_TO_1722_1],
                                i_eth_tx_lp[AVB1722_1_TO_MAC],
                                i_eth_cfg[MAC_CFG_TO_1722_1],
                                c_ptp[PTP_TO_1722_1],
                                otp_ports0);
      }
    }
  }

  return 0;
}

// The main application control task
[[combinable]]
void application_task(client interface avb_interface avb,
                      server interface avb_1722_1_control_callbacks i_1722_1_entity)
{
  const unsigned default_sample_rate = 48000;
  unsigned char aem_identify_control_value = 0;

  // Initialize the media clock
  avb.set_device_media_clock_type(0, DEVICE_MEDIA_CLOCK_INPUT_STREAM_DERIVED);
  avb.set_device_media_clock_rate(0, default_sample_rate);
  avb.set_device_media_clock_state(0, DEVICE_MEDIA_CLOCK_STATE_ENABLED);
  avb.set_device_media_clock_source(0, 0);

  for (int j=0; j < AVB_NUM_SOURCES; j++)
  {
    const int channels_per_stream = AVB_NUM_MEDIA_INPUTS/AVB_NUM_SOURCES;
    int map[AVB_NUM_MEDIA_INPUTS/AVB_NUM_SOURCES];
    for (int i = 0; i < channels_per_stream; i++) map[i] = j ? j*channels_per_stream+i : j+i;
    avb.set_source_map(j, map, channels_per_stream);
    avb.set_source_format(j, AVB_FORMAT_MBLA_24BIT, default_sample_rate);
    avb.set_source_sync(j, 0);
    avb.set_source_channels(j, channels_per_stream);
  }

  for (int j=0; j < AVB_NUM_SINKS; j++)
  {
    const int channels_per_stream = AVB_NUM_MEDIA_OUTPUTS/AVB_NUM_SINKS;
    int map[AVB_NUM_MEDIA_OUTPUTS/AVB_NUM_SINKS];
    for (int i = 0; i < channels_per_stream; i++) map[i] = j ? j*channels_per_stream+i : j+i;
    avb.set_sink_map(j, map, channels_per_stream);
    avb.set_sink_format(j, AVB_FORMAT_MBLA_24BIT, default_sample_rate);
    avb.set_sink_sync(j, 0);
    avb.set_sink_channels(j, channels_per_stream);
  }

  while (1)
  {
    select
    {
      case i_1722_1_entity.get_control_value(unsigned short control_index,
                                            unsigned int &value_size,
                                            unsigned short &values_length,
                                            unsigned char values[]) -> unsigned char return_status:
      {
        return_status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;

        switch (control_index)
        {
          case DESCRIPTOR_INDEX_CONTROL_IDENTIFY:
              values[0] = aem_identify_control_value;
              values_length = 1;
              return_status = AECP_AEM_STATUS_SUCCESS;
            break;
        }

        break;
      }
      case i_1722_1_entity.set_control_value(unsigned short control_index,
                                            unsigned short values_length,
                                            unsigned char values[]) -> unsigned char return_status:
      {
        return_status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;

        switch (control_index) {
          case DESCRIPTOR_INDEX_CONTROL_IDENTIFY: {
            if (values_length == 1) {
              aem_identify_control_value = values[0];
              if (aem_identify_control_value) {
                debug_printf("IDENTIFY Ping\n");
              }
              return_status = AECP_AEM_STATUS_SUCCESS;
            }
            else
            {
              return_status = AECP_AEM_STATUS_BAD_ARGUMENTS;
            }
            break;
          }
        }
        break;
      }
      case i_1722_1_entity.get_signal_selector(unsigned short selector_index,
                                               unsigned short &signal_type,
                                               unsigned short &signal_index,
                                               unsigned short &signal_output) -> unsigned char return_status:
      {
        return_status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
        break;
      }
      case i_1722_1_entity.set_signal_selector(unsigned short selector_index,
                                               unsigned short signal_type,
                                               unsigned short signal_index,
                                               unsigned short signal_output) -> unsigned char return_status:
      {
        return_status = AECP_AEM_STATUS_NO_SUCH_DESCRIPTOR;
        break;
      }
    }
  }
}
