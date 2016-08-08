// Copyright (c) 2014-2016, XMOS Ltd, All rights reserved
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
#include "avb_conf.h"

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


// Ports required for the Ethernet Slice in slot 4
on tile[1]: in port p_rxclk = XS1_PORT_1J;
on tile[1]: in port p_rxer  = XS1_PORT_1P; 
on tile[1]: in port p_rxd   = XS1_PORT_4E; 
on tile[1]: in port p_rxdv  = XS1_PORT_1K;
on tile[1]: in port p_txclk = XS1_PORT_1I;
on tile[1]: out port p_txen = XS1_PORT_1L;
on tile[1]: out port p_txd  = XS1_PORT_4F;
on tile[1]: port p_smi_mdio = XS1_PORT_1M;
on tile[1]: port p_smi_mdc  = XS1_PORT_1N;
on tile[1]: clock eth_rxclk = XS1_CLKBLK_1;
on tile[1]: clock eth_txclk = XS1_CLKBLK_2;

// Ports required for the i2C interface to the CODECs and PLL on the AUDIO slice in slot 2
on tile[0]: port p_scl = XS1_PORT_1M;
on tile[0]: port p_sda = XS1_PORT_1N;

// Ports required for the I2S and clocks on the AUDIO slice in slot 2

on tile[0]: out buffered port:32 p_fs[1] = { XS1_PORT_1P }; // Low frequency PLL frequency reference
on tile[0]: out buffered port:32 p_i2s_lrclk = XS1_PORT_1I;
on tile[0]: out buffered port:32 p_i2s_bclk = XS1_PORT_1K;
on tile[0]: in port p_i2s_mclk = XS1_PORT_1E;
on tile[0]: out buffered port:32 p_aud_dout[2] = {XS1_PORT_1O, XS1_PORT_1H};
on tile[0]: in buffered port:32 p_aud_din[2] = {XS1_PORT_1J, XS1_PORT_1L};
on tile[0]: clock clk_i2s_bclk = XS1_CLKBLK_3;
on tile[0]: clock clk_i2s_mclk = XS1_CLKBLK_4;



on tile[0]: out port p_LEDS = XS1_PORT_4F;                 //LED1 = bit0;LED1=bit=1;
on tile[0]: out port p_CODEC_RST_N = XS1_PORT_4E;          //bit0

// I2C addresses for the CODECS
const int codec1_addr = 0x48;
const int codec2_addr = 0x49;

// Register Addresses for the CS4270 CODEC on the AUDIO slice
#define CODEC_DEV_ID_ADDR           0x01
#define CODEC_PWR_CTRL_ADDR         0x02
#define CODEC_MODE_CTRL_ADDR        0x03
#define CODEC_ADC_DAC_CTRL_ADDR     0x04
#define CODEC_TRAN_CTRL_ADDR        0x05
#define CODEC_MUTE_CTRL_ADDR        0x06
#define CODEC_DACA_VOL_ADDR         0x07
#define CODEC_DACB_VOL_ADDR         0x08

#pragma unsafe arrays
[[always_inline]][[distributable]]
void buffer_manager_to_i2s(server i2s_callback_if i2s,
                           streaming chanend c_audio,
                           client interface i2c_master_if i2c,
                           out port p_CODEC_RST_N,
                           out port p_LEDS)
{
  audio_frame_t *unsafe p_in_frame;
  audio_double_buffer_t *unsafe double_buffer;
  int32_t *unsafe sample_out_buf;
  unsigned cur_sample_rate;
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

      // Bring the CODECs out of reset (They both share a reset line).
      p_CODEC_RST_N <: 0xF;      

      // Let the CODEC come out reset
      delay_microseconds(10);

      /* Power Control (Address: 0x02) */
      /* bit[7] : Freeze controls (FREEZE)       : Set to 1 for freeze
      * bit[6] : RESERVED                       :
      * bit[5] : Power Down ADC (PDN_ADC)       : Power down ADC
      * bit[4:2]: RESERVED                      :
      * bit[1] : Power Down DAC (PDN_DAC)       : Power down DAC
      * bit[0] : Power Down (PDN)               : Power down device
      */    

      i2c.write_reg(codec1_addr, CODEC_PWR_CTRL_ADDR, 0x01);       
      i2c.write_reg(codec2_addr, CODEC_PWR_CTRL_ADDR, 0x01);       

      /* Mode Control (Address: 0x03) */
      /* bit[7:6] : RESERVED                    :
      * bit[5:4] : ADC Functional Mode          : Slave Mode
      * bit[3:1] : Ratio Select                 : MCLK Divide by 4
      * bit[0]   : Popguard Transient Control   : Enabled
      */    

      i2c.write_reg(codec1_addr, CODEC_MODE_CTRL_ADDR, 0x35); 
      i2c.write_reg(codec2_addr, CODEC_MODE_CTRL_ADDR, 0x35);     

      /* ADC and DAC Control (Address: 0x04) */
      /*bit[7] : High Pass Filter Freeze CH A : Continuous value
      * bit[6] : High Pass Filter Freeze CH B : Continuous value
      * bit[5] : Digital loopback             : Disabled
      * bit[4:3]: DAC Interface format        : I2S, up to 24-bit data
      * bit[0] : ADC Digital Interface Format : I2S, up to 24-bit data
      */   

      i2c.write_reg(codec1_addr, CODEC_ADC_DAC_CTRL_ADDR, 0x09); 
      i2c.write_reg(codec2_addr, CODEC_ADC_DAC_CTRL_ADDR, 0x09);           
          
      /* Transition Control (Address: 0x05) */
      /*bit[7] : DAC Single Volume (DAC_SNGL_VOL)   : Signal volume enabled
      * bit[6] : Soft Ramp  (DAC_SOFT)              : Disabled
      * bit[5] : Zero Cross Enable (DAC_ZC)         : Enabled
      * bit[4:1]: Invert Signal Polarity            : No inversion on any ADC or DAC channels
      * bit[0] : De-Emphasis Control (DE_EMPH)      : No De-emphasis applied
      */ 

      i2c.write_reg(codec1_addr, CODEC_TRAN_CTRL_ADDR, 0x60); 
      i2c.write_reg(codec2_addr, CODEC_TRAN_CTRL_ADDR, 0x60);   

      /* Mute Control (Address: 0x06) */
      /*bit[7:6]: RESERVED                          : 
      * bit[5]  : Auto Mute (AUTO_MUTE)             : Disabled
      * bit[4:3]: ADC Channel Mute (MUTE_ADC_CHA/B) : Disabled
      * bit[2]  : Mute Polarity (MUTE_POL)          : Low
      * bit[1:0]: DAC Channel Mute (MUTE_DAC_CHA/B) : Disabled
      */ 

      i2c.write_reg(codec1_addr, CODEC_TRAN_CTRL_ADDR, 0x00); 
      i2c.write_reg(codec2_addr, CODEC_TRAN_CTRL_ADDR, 0x00);

      /*  DAC Channel A Volume Control (Address: 0x7) */
      /*bit[7:0]: DAC Channel A Volume Control     : 0dB
      */ 

      i2c.write_reg(codec1_addr, CODEC_DACA_VOL_ADDR, 0x00); 
      i2c.write_reg(codec2_addr, CODEC_DACA_VOL_ADDR, 0x00);

      /*  DAC Channel B Volume Control (Address: 0x8) */
      /*bit[7:0]: DAC Channel B Volume Control     : 0dB
      */ 

      i2c.write_reg(codec1_addr, CODEC_DACB_VOL_ADDR, 0x00); 
      i2c.write_reg(codec2_addr, CODEC_DACB_VOL_ADDR, 0x00);

      /* Power Control (Address: 0x02) */
      /* Disable the Device power down */
      i2c.write_reg(codec1_addr, CODEC_PWR_CTRL_ADDR, 0x00);       
      i2c.write_reg(codec2_addr, CODEC_PWR_CTRL_ADDR, 0x00);

      /* LEDS */
      p_LEDS <: 0x3;      

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
        p_in_frame->samples[index] = sample;
      }
      break;

    case i2s.send(size_t index) -> int32_t sample:
    
     unsafe {
        if (index == 0) {
          c_audio :> sample_out_buf;
        }
        sample = sample_out_buf[index];
        if (index == (AVB_NUM_MEDIA_INPUTS-1)) {
          tmr :> p_in_frame->timestamp;
          audio_frame_t *unsafe new_frame = audio_buffers_swap_active_buffer(*double_buffer);
          c_audio <: p_in_frame;
          p_in_frame = new_frame;
        }
      }
      break; // End of send
    }
  }
}


[[combinable]]
void LAN8710_phy_driver(client interface smi_if smi,
                client interface ethernet_cfg_if eth) {
  ethernet_link_state_t link_state = ETHERNET_LINK_DOWN;
  ethernet_speed_t link_speed = LINK_100_MBPS_FULL_DUPLEX;
  const int link_poll_period_ms = 1000;
  const int phy_address = 0x0;
  timer tmr;
  int phyStatus_speed;
  int t;
  tmr :> t;

 // Set the latency accross the PHY
 eth.set_ingress_timestamp_latency(0, LINK_100_MBPS_FULL_DUPLEX, 500);
 eth.set_egress_timestamp_latency(0, LINK_100_MBPS_FULL_DUPLEX, 50);

  while (smi_phy_is_powered_down(smi, phy_address));

  // Enable the AutoNegotiation and advertise 10/100Mbit capability
  smi_configure(smi, phy_address, LINK_100_MBPS_FULL_DUPLEX, SMI_ENABLE_AUTONEG);  

  // Periodically check the link status
  while (1) {
    select {
    case tmr when timerafter(t) :> t:
      ethernet_link_state_t new_state = smi_get_link_state(smi, phy_address);
      // Read LAN8710 status register (0x1F) bits 4:2 to get the current link speed
      if (new_state == ETHERNET_LINK_UP) {
        phyStatus_speed = (smi.read_reg(phy_address, 0x1F) >> 2) & 7;
        if(phyStatus_speed==0x5){
            link_speed = LINK_10_MBPS_FULL_DUPLEX; 
        }  else if (phyStatus_speed==0x6){
            link_speed = LINK_100_MBPS_FULL_DUPLEX;
        }
      }
      if (new_state != link_state) {
        link_state = new_state;
        eth.set_link_state(0, new_state, link_speed);
      }
      t += link_poll_period_ms * XS1_TIMER_KHZ;
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

  // I2S and audio buffering interfaces
  i2s_callback_if i_i2s;
  streaming chan c_audio;
  interface push_if i_audio_in_push;
  interface pull_if i_audio_in_pull;
  interface push_if i_audio_out_push;
  interface pull_if i_audio_out_pull;

  par
  {

    on tile[1]: mii_ethernet_rt_mac(i_eth_cfg, NUM_ETH_CFG_CLIENTS,
                         i_eth_rx_lp, NUM_ETH_RX_LP_CLIENTS,
                         i_eth_tx_lp, NUM_ETH_TX_LP_CLIENTS,
                         c_eth_rx_hp,
                         c_eth_tx_hp,
                         p_rxclk, p_rxer, p_rxd, p_rxdv,
                         p_txclk, p_txen, p_txd,
                         eth_rxclk, eth_txclk,
                         RX_BUFSIZE_WORDS,
                         TX_BUFSIZE_WORDS,
                         ETHERNET_DISABLE_SHAPER);

    on tile[1].core[0]: LAN8710_phy_driver(i_smi, i_eth_cfg[MAC_CFG_TO_PHY_DRIVER]);

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

    on tile[0]: [[distribute]] i2c_master(i_i2c, NUM_I2C_IFS, p_scl, p_sda, 100);



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

    on tile[0]: [[distribute]] buffer_manager_to_i2s(i_i2s, c_audio, i_i2c[I2S_TO_I2C], p_CODEC_RST_N, p_LEDS);

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
