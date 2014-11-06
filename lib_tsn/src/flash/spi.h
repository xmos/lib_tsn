#ifndef SPI_H
#define SPI_H

#include <xs1.h>

#ifdef __spi_conf_h_exists__
#include "spi_conf.h"
#endif

#ifndef SPI_CLK_MHZ
#define SPI_CLK_MHZ              25
#endif

#ifdef __XC__

/** Struct containing ports and clocks used to access a flash device. */
typedef struct fl_spi_ports {
    buffered in port:8 spiMISO;  /**< Master input, slave output (MISO) port. */
    out port spiSS;              /**< Slave select (SS) port. */
    buffered out port:32 spiCLK; /**< Serial clock (SCLK) port. */
    buffered out port:8 spiMOSI; /**< Master output, slave input (MOSI) port. */
    clock spiClkblk;             /**< Clock block for use with SPI ports. */
} fl_spi_ports;

interface spi_interface {
    /** This function issues a single command without parameters to the SPI,
     * and reads up to 4 bytes status value from the device.
     *
     * \param cmd        command value - listed above
     *
     * \param returnBytes The number of bytes that are to be read from the
     *                    device after the command is issued. 0 means no bytes
     *                    will be read.
     *
     * \returns the read bytes, or zero if no bytes were requested. If multiple
     * bytes are requested, then the last byte read is in the least-significant
     * byte of the return value.
     */
    int command_status(int cmd, unsigned returnBytes);

    /** This function issues a single command with a 3-byte address parameter
     * and an optional data-set to be output to or input form the device.
     *
     * \param cmd        command value - listed above
     *
     * \param address    the address to send to the SPI device. Only the least
     *                   significant 24 bits are used.
     *
     * \param data       an array of data that contains either data to be written to
     *                   the device, or which is used to store that that is
     *                   read from the device.
     *
     * \param returnBytes If positive, then this is the number of bytes that
     *                    are to be read from the device, into ``data``. If
     *                    negative, then this is (minus) the number of bytes to
     *                    be written to the device from ``data``. 0 means no
     *                    bytes will be read or written.
     *
     */
    void command_address_status(int cmd, unsigned int address, unsigned char data[], int returnBytes);
};

/** Task that implements a SPI interface to serial flash, typically the boot flash.
  *
  * Can be combined or distributed into other tasks.
  *
  * \param i_spi        server interface of type ``spi_interface``
  * \param spi_ports   reference to a ``fl_spi_ports`` structure containing the SPI flash ports and clockblock
  */
[[distributable]]
void spi_task(server interface spi_interface i_spi, fl_spi_ports &spi_ports);
#endif

#endif
