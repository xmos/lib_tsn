TSN library change log
======================

7.0.0
-----
  * Library changed to new structure and tools 14 compatibility added
  * Support added for new version 3 of Ethernet library and Gigabit Ethernet on xCORE-200
  * Support added for new version 2 of I2S/TDM library
  * Audio buffering performance improvements for higher channel count applications
  * Support added for 1722.1 Enitity Firmware Upgrade (EFU) using new Quad SPI flash library
  * Support added for 1722.1 ACMP Fast Connect
  * Support added for 1722.1 AECP sample rate change via GET/SET_SAMPLING_RATE and GET/SET_STREAM_FORMAT commands
  * Support added for 1722.1 AECP GET/SET_SIGNAL_SELECTOR commands
  * Current value fields in 1722.1 descriptors are now updated to reflect the current set value
  * Bug fix for gPTP number of lost reponses not being reset on link up event
  * Unimplemented 1722.1 commands now return the correct NOT_IMPLEMENTED status response
  * Resolved bug in 1722.1 ACMP disconnection caused by stream info not being zeroed

6.3.1
-----
  * Bug fix for excessive Talker AVTP presentation time being absorbed in the FIFOs for a short period at start
  * Fixes regression in bad gPTP pdelay follow up detection
  * Bug fix for reported base audio clusters in AEM stream descriptors

6.3.0
-----
  * MEDIA_CLOCK_SOURCE bit now set in 1722.1 ADP Talker Capabilities
  * 1722.1 GET_COUNTERS command added for CLOCK_DOMAIN descriptor
  * Minor bug fix in gPTP where multiple pdelay responses were not triggering AVnu specific behaviour
  * Change to SRP interface to allow SRP to control the joining of VLANs via MVRP
  * Max frame size reported by SRP changed to reflect the current set sample rate instead of the max supported

  * Changes to dependencies:

    - sc_ethernet: 2.3.2rc0 -> 2.3.3beta0

      + Change to rounding of Qav slope calculation

6.2.2
-----
  * PTP clock accuracy is now reported to be within 25 ns by BMCA
  * PTP offset scaled log variance is now set to the correct unkown value (0x436A) per IEEE P802.1AS-Cor-1
  * Grandmaster timeBaseIndicator and lastGmFreqChange parameters are now set in the PTP sync follow up TLV
  * Pdelay exchanges are marked invalid and asCapable reset if the delay is measured as negative
  * Fixed issue with lost PTP messages being counted twice, causing a premature asCapable reset

6.2.1
-----
  * Fix potential parallel usage violation on PTP client function

6.2.0
-----
  * Ethernet AVB server now configures auto-negotiation on the PHY
  * State of MAAP and PTP now reset on link up of single port configuration
  * Minor bug fixes to 1722.1 descriptors and commands

6.1.2
-----
  * Various minor SRP compliance fixes

6.1.1
-----
  * Various gPTP AVnu compliance fixes (June 2014 report)

6.1.0
-----
  * Support added for sw_avb_lc single port reference design
  * gptp.c moved to XC
  * Misc M*RP AVnu compliance fixes
  * gPTP AVnu compliance fixes

  * Changes to dependencies:

    - sc_ethernet: 2.3.1rc0 -> 2.3.2rc0

      + Updated timestamp adjustements for LAN8710A PHY to realistic values

6.0.7
-----

  * Changes to dependencies:

    - sc_ethernet: 2.3.0rc0 -> 2.3.1rc0

      + Fix invalid inter-frame gaps.

6.0.6
-----
  * Reverted change to 1722 introduced in 6.0.3 that caused media clock to unlock

6.0.5
-----
  * Bug fix to prevent compile error when Talker is disabled
  * Update to 1722 MAAP to fix non-compliance issue on conflict check

6.0.4
-----
  * Updates design guide documentation to include AVB-DC details
  * SPI task updated to take a structure with ports
  * Bug fix on cd length of acquire command response
  * Added EFU mode and address access flags to ADP capabilities

6.0.3
-----
  * Firmware upgrade functionality changed to support START_OPERATION commands to erase the flash
  * Several SRP bug fixes that would cause long connect/disconnection sequences to fail

6.0.2
-----
  * Interim release for production manufacture

6.0.1
-----
  * VLAN ID is now reported via 1722.1 ACMP
  * Fixed XC pointer issue for v13.0.1 tools

6.0.0
-----
  * First release supporting daisy chain AVB
  * Refactoring sw_avb modules into sc_avb

5.2.0
-----
  * Numerous updates to support xTIMEcomposer v12 tools, including updated sc_ethernet
  * 1722.1 Draft 21 support for ADP, ACMP and a subset of AECP including an AEM descriptor set
  * Old TCP/IP based Attero Tech application replaced with a 1722.1 demo
  * Added ability to arbitrarily map between channels in sinked streams and audio outputs
  * 1722 MAAP rewritten to optimise memory and improve compliance to standard
  * AVB status API replaced with new weak attribute hooks
  * Support added for CS2100 variant of PLL
  * sc_xlog printing removed, replaced with XScope
  * Support removed for XDK/XAI, XC-2 and XC-3 dev kits
  * Application support removed for Open Sound Control

5.1.2
-----
  * PTP fix to correct step in g_ptp_adjust (commit #1548fa5ce7)
  * Software support added for CS2100 PLL.
  * Media clock recovery PID tuned to decrease settle time and amplitude of oscillations
  * Fixes to app_xr_avb_lc_demo to work with channel counts < 8
  * Transport stream interface
  * 1722/61883-4 packet encapsulation
  * Update to ethernet and tcp package dependencies

5.1.1
-----
  * Field update module added
  * I2S slave functionality added

5.1.0
-----
  * 802.1Qat support
  * Partial (beta) 1722.1 support
  * Clock recovery corrections for 8kHz and >48kHz
  * 1722 packet format corrections
  * 1722 timestamp corrections
  * Stream lock/unlock more predictable
  * Test harnesses for various features
  * SRP state machine corrections
  * SRP state machine drives stream transmission

5.0.0
-----
  * New control API
  * 1722 MAAP support
  * Standard updates
  * Optimizations
  * See design guide for new release details

4.1.0
-----
  * Move to new build system

4.0.0
-----
  * Fixed missing functionality in media clock server
  * Small changes media server API - see demos for examples
  * Optimized audio transport for local listener streams
  * Major rewrite, many internal APIs changed, overall performance improvements
  * Added gigabit ethernet support
  * Added flexible internal routing (local streams) with simplified
    API, framework is much more powerful for many-channel applications
  * Rewritten audio_clock_recovery as more flexible media_clock_server
  * Added demos for audio interface board
  * Added 8-channel TDM audio interface
  * Added uip IP/UDP/TCP server for adding configuration layer
  * Various bug fixes


