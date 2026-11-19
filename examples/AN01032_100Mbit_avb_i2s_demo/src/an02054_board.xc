// Board support for the AN02054 dual-Ethernet board (XU316-1024-QF60B, 25 MHz crystal).
#include <xs1.h>
#include <platform.h>
#include "an02054_board.h"

// Shared hard reset for PHY 0 and the codec. Bit 3 of the port is connected to PERIPH_RST_N.
static void an02054_hard_reset(out port p_rst)
{
  p_rst <: 0x00;
  delay_microseconds(100);   // DP83825I needs 25 us minimum; the codec needs a reset pulse too
  p_rst <: 0x08;             // Bit 3 high releases PERIPH_RST_N
  delay_milliseconds(55);    // DP83825I needs 50 ms before SMI access
}

rmii_port_timing_t an02054_phy0_port_timing(void)
{
  // Values copied from lib_ethernet's dual-100M XU316 board support for the PHY 0 clock master.
  // They have not been tuned on this board.
  rmii_port_timing_t port_timing = {0};
  port_timing.clk_delay_tx_rising = 1;
  port_timing.clk_delay_tx_falling = 1;
  port_timing.clk_delay_rx_rising = 0;
  port_timing.clk_delay_rx_falling = 0;
  port_timing.pad_delay_rx = 1;
  return port_timing;
}

void an02054_enable_codec_mclk(void)
{
  // Application clock divider: bit 31 selects the Secondary PLL, bit 16 = 0 enables the divider,
  // and the divide field X = 0 gives divide-by-2. Output appears on X1D11.
  write_sswitch_reg(get_local_tile_id(), XS1_SSWITCH_SS_APP_CLK_DIVIDER_NUM, 0x80000000);
}

// Writes one register and returns 0 on success, or the register address + 256 on failure.
static int codec_write(client interface i2c_master_if i2c, uint8_t reg, uint8_t value)
{
  if (i2c.write_reg(AN02054_CODEC_ADDR, reg, value) != I2C_REGOP_SUCCESS) {
    return reg + 256;
  }
  return 0;
}

int an02054_codec_init(client interface i2c_master_if i2c)
{
  int err = 0;

  // Let the codec leave reset (the PHY driver releases the shared reset after about 55 ms)
  delay_milliseconds(100);

  // Page 0: software reset, clock dividers for DAC and ADC, I2S format (SLAA557 4.0.3 / 4.0.4)
  err |= codec_write(i2c, 0x00, 0x00);
  err |= codec_write(i2c, 0x01, 0x01);  // software reset
  err |= codec_write(i2c, 0x0B, 0x81);  // NDAC = 1, powered
  err |= codec_write(i2c, 0x0C, 0x84);  // MDAC = 4, powered
  err |= codec_write(i2c, 0x0D, 0x00);  // DOSR = 128
  err |= codec_write(i2c, 0x0E, 0x80);
  err |= codec_write(i2c, 0x1B, 0x20);  // I2S, 24-bit, BCLK and WCLK inputs (codec is slave)
  err |= codec_write(i2c, 0x3C, 0x01);  // DAC PRB_P1

  // Page 1: analog power, headphone/line-out drivers routed from the DAC
  err |= codec_write(i2c, 0x00, 0x01);
  err |= codec_write(i2c, 0x01, 0x08);  // disable internal crude AVdd
  err |= codec_write(i2c, 0x02, 0x00);  // enable master analog power control
  err |= codec_write(i2c, 0x7B, 0x01);  // reference charging time 40 ms
  err |= codec_write(i2c, 0x14, 0x25);  // headphone soft stepping
  err |= codec_write(i2c, 0x0A, 0x00);  // input common mode 0.9 V
  err |= codec_write(i2c, 0x0C, 0x08);  // route left DAC to HPL
  err |= codec_write(i2c, 0x0D, 0x08);  // route right DAC to HPR
  err |= codec_write(i2c, 0x10, 0x00);  // unmute HPL driver
  err |= codec_write(i2c, 0x11, 0x00);  // unmute HPR driver
  err |= codec_write(i2c, 0x09, 0x30);  // power up HPL and HPR

  // Page 0: power up both DAC channels from the left and right data, unmute the volume
  err |= codec_write(i2c, 0x00, 0x00);
  err |= codec_write(i2c, 0x3F, 0xD4);  // L and R DAC powered, Ldata to LDAC, Rdata to RDAC
  err |= codec_write(i2c, 0x40, 0x00);  // unmute DAC digital volume, independent control

  // ADC: NADC = 1, MADC = 4, AOSR = 128 gives 48 kHz from 24.576 MHz (SLAA557 4.0.4)
  err |= codec_write(i2c, 0x12, 0x81);
  err |= codec_write(i2c, 0x13, 0x84);
  err |= codec_write(i2c, 0x14, 0x80);
  err |= codec_write(i2c, 0x3D, 0x01);  // ADC PRB_R1

  // Page 1: line input routing (20K) and MicPGA gain (0 dB channel gain at 6 dB register setting)
  err |= codec_write(i2c, 0x00, 0x01);
  err |= codec_write(i2c, 0x01, 0x08);
  err |= codec_write(i2c, 0x02, 0x00);
  err |= codec_write(i2c, 0x0A, 0x00);
  err |= codec_write(i2c, 0x3D, 0x00);  // ADC PTM_R4
  err |= codec_write(i2c, 0x47, 0x32);  // MicPGA startup delay 3.1 ms
  err |= codec_write(i2c, 0x7B, 0x01);
  err |= codec_write(i2c, 0x34, 0x80);  // IN1L to left positive, 20K
  err |= codec_write(i2c, 0x36, 0x80);  // common mode to left negative, 20K
  err |= codec_write(i2c, 0x37, 0x80);  // IN1R to right positive, 20K
  err |= codec_write(i2c, 0x39, 0x80);  // common mode to right negative, 20K
  err |= codec_write(i2c, 0x3B, 0x0C);  // unmute left MicPGA, 6 dB register setting
  err |= codec_write(i2c, 0x3C, 0x0C);  // unmute right MicPGA, 6 dB register setting

  // Page 0: power up both ADC channels and unmute the digital volume
  err |= codec_write(i2c, 0x00, 0x00);
  err |= codec_write(i2c, 0x51, 0xC0);
  err |= codec_write(i2c, 0x52, 0x00);

  return err;
}

[[combinable]]
void dp83825_phy_driver(client interface smi_if smi,
                        client interface ethernet_cfg_if eth,
                        out port p_rst)
{
  ethernet_link_state_t link_state = ETHERNET_LINK_DOWN;
  ethernet_speed_t link_speed = LINK_100_MBPS_FULL_DUPLEX;
  const int link_poll_period_ms = 1000;
  timer tmr;
  int t;

  an02054_hard_reset(p_rst);

  while (smi_phy_is_powered_down(smi, AN02054_PHY0_ADDR));

  // Enable autonegotiation and advertise 10/100 Mbit
  smi_configure(smi, AN02054_PHY0_ADDR, LINK_100_MBPS_FULL_DUPLEX, SMI_ENABLE_AUTONEG);

  tmr :> t;
  while (1) {
    select {
    case tmr when timerafter(t) :> t:
      ethernet_link_state_t new_state = smi_get_link_state(smi, AN02054_PHY0_ADDR);
      if (new_state == ETHERNET_LINK_UP) {
        link_speed = smi_get_link_speed(smi, AN02054_PHY0_ADDR);
      }
      if (new_state != link_state) {
        link_state = new_state;
        eth.set_link_state(0, link_state, link_speed);
      }
      t += link_poll_period_ms * XS1_TIMER_KHZ;
      break;
    }
  }
}
