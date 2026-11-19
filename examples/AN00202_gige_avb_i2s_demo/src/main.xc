// Copyright (c) 2014-2017, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <string.h>
#include <xscope.h>
#include "i2s.h"
#include "i2c.h"
#include "avb.h"
#include "an02054_board.h"
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
fl_QSPIPorts qspi_ports =
{
  PORT_SQI_CS,
  PORT_SQI_SCLK,
  PORT_SQI_SIO,
  on tile[0]: XS1_CLKBLK_1
};



// PHY 0 RMII (tile 0). Data uses the upper two bits of the 4-bit ports.
in port p_clk50 = PHY0_CLK_50M;
in port p_rxdv  = PHY0_RX_DV;
out port p_txen = PHY0_TX_EN;
port p_txd      = PHY0_TXD_4BIT;
port p_rxd      = PHY0_RXD_4BIT;
clock eth_rxclk = on tile[0]: XS1_CLKBLK_3;
clock eth_txclk = on tile[0]: XS1_CLKBLK_4;

// SMI management for PHY 0 (tile 1)
port p_smi_mdio = PORT_SMI_MDIO;
port p_smi_mdc  = PORT_SMI_MDC;

// Shared PHY and codec reset (tile 1)
out port p_phy_rst = PORT_PERIPH_RST;

// Codec control bus on the 8-bit port (SCL bit 4, SDA bit 5) (tile 0)
port p_i2c = CODEC_I2C_8BIT;

// Unused media clock reference output (tile 0). The board has no reference clock output.
out buffered port:32 p_fs[1] = { PORT_UNUSED_FS };

// Stereo I2S on tile 1. MCLK comes from the Secondary PLL on X1D11, read back on port 1D.
out buffered port:32 p_i2s_lrclk = PORT_I2S_LRCLK;
out port p_i2s_bclk = PORT_I2S_BCLK;
in port p_i2s_mclk = PORT_MCLK_APLL;
out buffered port:32 p_aud_dout[1] = {PORT_I2S_DAC_DATA};
in buffered port:32 p_aud_din[1] = {PORT_I2S_ADC_DATA};
clock clk_i2s_bclk = on tile[1]: XS1_CLKBLK_2;

#pragma unsafe arrays
[[always_inline]][[distributable]]
void buffer_manager_to_i2s(server i2s_frame_callback_if i2s,
                           streaming chanend c_audio,
                           client interface i2c_master_if i2c)
{
  audio_frame_t *unsafe p_in_frame;
  audio_double_buffer_t *unsafe double_buffer;
  int32_t *unsafe sample_out_buf = NULL;
  unsigned cur_sample_rate;
  timer tmr;

  // Start the codec master clock before the codec is configured
  an02054_enable_codec_mclk();

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
      // I2S has 32 bits per sample slot. *2 as 2 channels
      const unsigned num_bits = 64;
      const unsigned mclk = 512 * 48000;
      // Calculate the MCLK to BCLK ratio using the current sample rate and bits per sample
      i2s_config.mclk_bclk_ratio = mclk / ( cur_sample_rate * num_bits);

      // Configure the TLV320AIC3204 (slave, I2S, 24-bit, 48 kHz)
      if (an02054_codec_init(i2c) != 0) {
        debug_printf("Codec configuration failed\n");
      }
      break;

    case i2s.restart_check() -> i2s_restart_t restart:

      unsafe {
        /* Ensure we have received our first sample buf first and then
           check for magic value which indicates a sample rate change */
        if (sample_out_buf != NULL && sample_out_buf[AVB_NUM_MEDIA_INPUTS + AVB_NUM_MEDIA_OUTPUTS]) {
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

    case i2s.receive(size_t num_in, int32_t samples[num_in]):
      for(int index = 0; index < num_in; index++){
        unsafe {
          p_in_frame->samples[index] = samples[index];
        }
      }
      break;

    case i2s.send(size_t num_out, int32_t samples[num_out]):
      unsafe{
        c_audio :> sample_out_buf;
        for(int index = 0; index < num_out; index++){
          samples[index] = sample_out_buf[index];
        }

        tmr :> p_in_frame->timestamp;
        audio_frame_t *unsafe new_frame = audio_buffers_swap_active_buffer(*double_buffer);
        c_audio <: p_in_frame;
        p_in_frame = new_frame;

      }
      break; // End of send
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
  i2s_frame_callback_if i_i2s;
  streaming chan c_audio;
  interface push_if i_audio_in_push;
  interface pull_if i_audio_in_pull;
  interface push_if i_audio_out_push;
  interface pull_if i_audio_out_pull;

  par
  {
    // PHY 0 RMII MAC on tile 0 (the Ethernet pins are on tile 0)
    on tile[0]: rmii_ethernet_rt_mac(i_eth_cfg, NUM_ETH_CFG_CLIENTS,
                         i_eth_rx_lp, NUM_ETH_RX_LP_CLIENTS,
                         i_eth_tx_lp, NUM_ETH_TX_LP_CLIENTS,
                         c_eth_rx_hp,
                         c_eth_tx_hp,
                         p_clk50,
                         p_rxd, null, USE_UPPER_2B,
                         p_rxdv,
                         p_txen,
                         p_txd, null, USE_UPPER_2B,
                         eth_rxclk, eth_txclk,
                         an02054_phy0_port_timing(),
                         RX_BUFSIZE_WORDS,
                         TX_BUFSIZE_WORDS,
                         ETHERNET_DISABLE_SHAPER);

    // DP83825I PHY 0 driver and shared reset (tile 1)
    on tile[1].core[0]: dp83825_phy_driver(i_smi, i_eth_cfg[MAC_CFG_TO_PHY_DRIVER], p_phy_rst);

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

    // Codec control bus on the 8-bit port (tile 0)
    on tile[0]: i2c_master_single_port(i_i2c, NUM_I2C_IFS, p_i2c, 100, 4, 5, 0);

    // Stereo I2S master on tile 1, clocked by the MCLK read back on port 1D
    on tile[1]: {
      i2s_frame_master(i_i2s,
                 p_aud_dout, AVB_NUM_MEDIA_OUTPUTS/2,
                 p_aud_din, AVB_NUM_MEDIA_INPUTS/2,
                 32,
                 p_i2s_bclk,
                 p_i2s_lrclk,
                 p_i2s_mclk,
                 clk_i2s_bclk);
    }

    on tile[1]: buffer_manager_to_i2s(i_i2s, c_audio, i_i2c[I2S_TO_I2C]);

    on tile[1]: audio_buffer_manager(c_audio, i_audio_in_push, i_audio_out_pull, c_media_ctl[0], AUDIO_I2S_IO);

    on tile[1]: audio_input_sample_buffer(i_audio_in_push, i_audio_in_pull);

    on tile[1]: avb_1722_talker(c_ptp[PTP_TO_TALKER],
                                c_eth_tx_hp,
                                c_talker_ctl[0],
                                AVB_NUM_SOURCES,
                                i_audio_in_pull);

    on tile[1]: audio_output_sample_buffer(i_audio_out_push, i_audio_out_pull);

    on tile[1]: avb_1722_listener(c_eth_rx_hp,
                                  c_buf_ctl[0],
                                  null,
                                  c_listener_ctl[0],
                                  AVB_NUM_SINKS,
                                  i_audio_out_push);

    on tile[0]: {
      char mac_address[6];
      if (otp_board_info_get_mac(otp_ports0, 0, mac_address) == 0) {
        const char mac_address_manual[] = {0x12, 0x34, 0x56, 0x67, 0x89, 0xab};
        debug_printf("No MAC address programmed in OTP, falling back to %x:%x:%x:%x:%x:%x\n",
            mac_address_manual[0], mac_address_manual[1], mac_address_manual[2],
            mac_address_manual[3], mac_address_manual[4], mac_address_manual[5]);
        memcpy(mac_address, mac_address_manual, sizeof(mac_address));
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
