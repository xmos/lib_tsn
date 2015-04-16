// Copyright (c) 2015, XMOS Ltd, All rights reserved
#include <xs1.h>
#include <platform.h>
#include <print.h>
#include <xccompat.h>
#include <string.h>
#include <xscope.h>
#include "audio_i2s.h"
#include "i2c.h"
#include "avb.h"
#include "audio_clock_CS2100CP.h"
#include "xassert.h"
#include "debug_print.h"
#include "media_fifo.h"
#include "simple_demo_controller.h"
#include "avb_1722_1_adp.h"
#include "app_config.h"
#include "avb_1722.h"
#include "gptp.h"
#include "media_clock_server.h"
#include "avb_1722_1.h"
#include "avb_srp.h"
#include "aem_descriptor_types.h"
#include "ethernet.h"
#include "smi.h"

on tile[0]: otp_ports_t otp_ports0 = OTP_PORTS_INITIALIZER;
on tile[1]: otp_ports_t otp_ports1 = OTP_PORTS_INITIALIZER;

on tile[1]: rgmii_ports_t rgmii_ports = RGMII_PORTS_INITIALIZER;

on tile[1]: port p_smi_mdio = XS1_PORT_1C;
on tile[1]: port p_smi_mdc = XS1_PORT_1D;
on tile[1]: port p_eth_reset = XS1_PORT_4A;

on tile[1]: out port p_leds_row = XS1_PORT_4C;
on tile[1]: out port p_leds_column = XS1_PORT_4D;

on tile[0]: port p_i2c = XS1_PORT_4A;

//***** AVB audio ports ****
on tile[0]: out buffered port:32 p_fs[1] = { XS1_PORT_1A };
on tile[0]: i2s_ports_t i2s_ports =
{
  XS1_CLKBLK_3,
  XS1_CLKBLK_4,
  XS1_PORT_1F,
  XS1_PORT_1H,
  XS1_PORT_1G
};

on tile[0]: out buffered port:32 p_aud_dout[4] = {XS1_PORT_1M, XS1_PORT_1N, XS1_PORT_1O, XS1_PORT_1P};
on tile[0]: in buffered port:32 p_aud_din[4] = {XS1_PORT_1I, XS1_PORT_1J, XS1_PORT_1K, XS1_PORT_1L};

on tile[0]: out port p_audio_shared = XS1_PORT_8C;

#if AVB_DEMO_ENABLE_LISTENER
media_output_fifo_data_t ofifo_data[AVB_NUM_MEDIA_OUTPUTS];
media_output_fifo_t ofifos[AVB_NUM_MEDIA_OUTPUTS];
#else
  #define ofifos null
#endif

#if AVB_DEMO_ENABLE_TALKER
media_input_fifo_data_t ififo_data[AVB_NUM_MEDIA_INPUTS];
media_input_fifo_t ififos[AVB_NUM_MEDIA_INPUTS];
#else
  #define ififos null
#endif

[[combinable]] void application_task(client interface avb_interface avb, server interface avb_1722_1_control_callbacks i_1722_1_entity);

#define CS4384_MODE_CTRL     0x02
#define CS4384_PCM_CTRL      0x03

#define CS5368_GCTL_MDE      0x01
#define CS5368_PWR_DN        0x06

[[distributable]] void audio_hardware_setup(client interface i2c_master_if i2c)
{
  audio_clock_CS2100CP_init(i2c, MASTER_TO_WORDCLOCK_RATIO);

  p_audio_shared <: 0b11000110;

  // DAC
  i2c.write_reg(0x18, CS4384_MODE_CTRL, 0b11000001);
  i2c.write_reg(0x18, CS4384_PCM_CTRL, 0b00010111);
  i2c.write_reg(0x18, CS4384_MODE_CTRL, 0b10000000);

  // ADC
  i2c.write_reg(0x4C, CS5368_GCTL_MDE, 0b10010000 | (0x01 << 2) | 0x03);
  i2c.write_reg(0x4C, CS5368_PWR_DN, 0);

  while (1) {
    select {
    }
  }
}

[[combinable]]
void ar8035_phy_driver(client interface smi_if smi,
                client interface ethernet_cfg_if eth) {
  ethernet_link_state_t link_state = ETHERNET_LINK_DOWN;
  ethernet_speed_t link_speed = LINK_1000_MBPS_FULL_DUPLEX;
  const int phy_reset_delay_ms = 1;
  const int link_poll_period_ms = 1000;
  const int phy_address = 0x4;
  timer tmr;
  int t;
  tmr :> t;
  p_eth_reset <: 0;
  delay_milliseconds(phy_reset_delay_ms);
  p_eth_reset <: 0xf;

  eth.set_ingress_timestamp_latency(0, LINK_1000_MBPS_FULL_DUPLEX, 300);
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
#if AVB_DEMO_ENABLE_TALKER
  PTP_TO_TALKER,
#endif
  PTP_TO_1722_1,
  NUM_PTP_CHANS
};

int main(void)
{
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
#if AVB_DEMO_ENABLE_TALKER
  chan c_talker_ctl[AVB_NUM_TALKER_UNITS];
#else
  #define c_talker_ctl null
#endif

#if AVB_DEMO_ENABLE_LISTENER
  chan c_listener_ctl[AVB_NUM_LISTENER_UNITS];
  chan c_buf_ctl[AVB_NUM_LISTENER_UNITS];
#else
  #define c_listener_ctl null
  #define c_buf_ctl null
#endif

  // Media control
  chan c_media_ctl[AVB_NUM_MEDIA_UNITS];
  interface media_clock_if i_media_clock_ctl;

  interface avb_interface i_avb[NUM_AVB_MANAGER_CHANS];
  interface avb_1722_1_control_callbacks i_1722_1_entity;
  i2c_master_if i2c[1];

  par
  {
    on tile[1]: rgmii_ethernet_mac(i_eth_rx_lp, NUM_ETH_RX_LP_CLIENTS,
                                   i_eth_tx_lp, NUM_ETH_TX_LP_CLIENTS,
                                   c_eth_rx_hp, c_eth_tx_hp,
                                   c_rgmii_cfg,
                                   rgmii_ports, 
                                   ETHERNET_DISABLE_SHAPER);

    on tile[1].core[0]: rgmii_ethernet_mac_config(i_eth_cfg, NUM_ETH_CFG_CLIENTS, c_rgmii_cfg);
    on tile[1].core[0]: ar8035_phy_driver(i_smi, i_eth_cfg[MAC_CFG_TO_PHY_DRIVER]);
  
    on tile[1]: smi(i_smi, p_smi_mdio, p_smi_mdc);

    on tile[0]: media_clock_server(i_media_clock_ctl,
                                   null,
                                   c_buf_ctl,
                                   AVB_NUM_LISTENER_UNITS,
                                   p_fs,
                                   i_eth_rx_lp[MAC_TO_MEDIA_CLOCK_PTP],
                                   i_eth_tx_lp[MEDIA_CLOCK_PTP_TO_MAC],
                                   i_eth_cfg[MAC_CFG_TO_MEDIA_CLOCK_PTP],
                                   c_ptp, NUM_PTP_CHANS,
                                   PTP_GRANDMASTER_CAPABLE);

    on tile[0]: [[distribute]] i2c_master_single_port(i2c, 1, p_i2c, 100, 0, 1, 0);
    on tile[0]: [[distribute]] audio_hardware_setup(i2c[0]);

    on tile[0]:
    {
#if AVB_DEMO_ENABLE_TALKER
      init_media_input_fifos(ififos, ififo_data, AVB_NUM_MEDIA_INPUTS);
#endif

#if AVB_DEMO_ENABLE_LISTENER
      init_media_output_fifos(ofifos, ofifo_data, AVB_NUM_MEDIA_OUTPUTS);
#endif
      media_ctl_register(c_media_ctl[0], ififos, AVB_NUM_MEDIA_INPUTS,
                         ofifos, AVB_NUM_MEDIA_OUTPUTS, 0);

      i2s_master(i2s_ports,
                 p_aud_din, AVB_NUM_MEDIA_INPUTS,
                 p_aud_dout, AVB_NUM_MEDIA_OUTPUTS,
                 MASTER_TO_WORDCLOCK_RATIO,
                 ififos,
                 ofifos);
    }

#if AVB_DEMO_ENABLE_TALKER
    // AVB Talker - must be on the same tile as the audio interface
    on tile[0]: avb_1722_talker(c_ptp[PTP_TO_TALKER],
                                c_eth_tx_hp,
                                c_talker_ctl[0],
                                AVB_NUM_SOURCES);
#endif

#if AVB_DEMO_ENABLE_LISTENER
    // AVB Listener
    on tile[0]: avb_1722_listener(c_eth_rx_hp,
                                  c_buf_ctl[0],
                                  null,
                                  c_listener_ctl[0],
                                  AVB_NUM_SINKS);
#endif
    

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
         avb_1722_1_maap_srp_task(otp_ports0,
                                  i_avb[AVB_MANAGER_TO_1722_1],
                                  i_1722_1_entity,
                                  null,
                                  i_eth_rx_lp[MAC_TO_1722_1],
                                  i_eth_tx_lp[AVB1722_1_TO_MAC],
                                  i_eth_cfg[MAC_CFG_TO_1722_1],
                                  c_ptp[PTP_TO_1722_1]);
       }
    }
  }

    return 0;
}

/** The main application control task **/
[[combinable]]
void application_task(client interface avb_interface avb, server interface avb_1722_1_control_callbacks i_1722_1_entity)
{  
#if AVB_DEMO_ENABLE_TALKER
  const int channels_per_stream = AVB_NUM_MEDIA_INPUTS/AVB_NUM_SOURCES;
  int map[AVB_NUM_MEDIA_INPUTS/AVB_NUM_SOURCES];
#endif
  const unsigned default_sample_rate = 48000;
  unsigned char aem_identify_control_value = 0;

  // Initialize the media clock
  avb.set_device_media_clock_type(0, DEVICE_MEDIA_CLOCK_INPUT_STREAM_DERIVED);
  avb.set_device_media_clock_rate(0, default_sample_rate);
  avb.set_device_media_clock_state(0, DEVICE_MEDIA_CLOCK_STATE_ENABLED);

#if AVB_DEMO_ENABLE_TALKER
  for (int j=0; j < AVB_NUM_SOURCES; j++)
  {
    avb.set_source_channels(j, channels_per_stream);
    for (int i = 0; i < channels_per_stream; i++)
      map[i] = j ? j*(channels_per_stream)+i  : j+i;
    avb.set_source_map(j, map, channels_per_stream);
    avb.set_source_format(j, AVB_SOURCE_FORMAT_MBLA_24BIT, default_sample_rate);
    avb.set_source_sync(j, 0); // use the media_clock defined above
  }
#endif

  avb.set_sink_format(0, AVB_SOURCE_FORMAT_MBLA_24BIT, default_sample_rate);

  while (1)
  {
    select
    {
      case i_1722_1_entity.get_control_value(unsigned short control_index,
                                            unsigned short &values_length,
                                            unsigned char values[AEM_MAX_CONTROL_VALUES_LENGTH_BYTES]) -> unsigned char return_status:
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
                                            unsigned char values[AEM_MAX_CONTROL_VALUES_LENGTH_BYTES]) -> unsigned char return_status:
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
    }
  }
}
