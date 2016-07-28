PTP Swapping Talker
=====================

This is a minimal 1722 talker with PTP and bare bones 1722.1 to allow streaming a single stream of audio. Media clock source is internal 100MHz reference.

It can be used to generate frequent transitions of PTP grandmaster and test a full endpoint with them.

1722 timestamps can be set to update with a delay after the grandmaster transition. This has been shown to target interesting corner cases in PTP, media clock recovery and their interaction.

Features:

   * programmable interval of transitioning PTP grandmaster to other endpoint and back to itself
   * stepping through a range of intervals between a configured minimum and maximum (e.g. 3, 4, 5, 6, 7 and 8 seconds)
   * configurable master PTP rate to adjust size of step change between other endpoint and this test talker
   * programmable delay of 1722 timestamps following grandmaster transition
   * stepping through a range of 1722 timestamp delay from 0 up to a configured value (e.g. 0, 1, 2 and 3 seconds)
