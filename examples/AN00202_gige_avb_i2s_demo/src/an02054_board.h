// Board support for the AN02054 dual-Ethernet board (XU316-1024-QF60B, 25 MHz crystal).
// Only PHY 0 (RMII) and the TLV320AIC3204 stereo codec are used.
#ifndef __an02054_board_h__
#define __an02054_board_h__

#include "smi.h"
#include "ethernet.h"
#include "i2c.h"

/** SMI address of PHY 0 (no pull straps, PHYADD = 0x0). */
#define AN02054_PHY0_ADDR 0x00

/** I2C device address of the TLV320AIC3204 (7-bit form). */
#define AN02054_CODEC_ADDR 0x18

/** Returns the RMII timing for PHY 0, which is the RMII clock master. */
rmii_port_timing_t an02054_phy0_port_timing(void);

/** Enable the Secondary PLL output on X1D11 (divide by 2, 24.576 MHz from 49.152 MHz).
 *  The PLL itself is configured by the SecondaryFrequency attribute in the XN file.
 *  Call from tile 0 before the codec is initialised. */
void an02054_enable_codec_mclk(void);

/** Initialise the TLV320AIC3204 as I2S slave, 24-bit, 48 kHz, with MCLK = 24.576 MHz.
 *  Writes follow TI SLAA557 sections 4.0.3 and 4.0.4.
 *  Returns 0 on success, or the register address that was NACKed plus 256. */
int an02054_codec_init(client interface i2c_master_if i2c);

/** DP83825I PHY 0 driver: hard-resets the PHY and codec, configures autonegotiation
 *  and reports link state to the MAC. Combinable. */
[[combinable]]
void dp83825_phy_driver(client interface smi_if smi,
                        client interface ethernet_cfg_if eth,
                        out port p_rst);

#endif
