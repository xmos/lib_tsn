// Copyright (c) 2011-2017, XMOS Ltd, All rights reserved

#include <xccompat.h>

#include "avb_1722_talker.h"
#include "default_avb_conf.h"

void avb1722_set_buffer_vlan(int vlan,
		unsigned char Buf0[])
{
	unsigned char *Buf = &Buf0[2];
	AVB_Frame_t *pEtherHdr = (AVB_Frame_t *) &(Buf[0]);

	CLEAR_AVBTP_VID(pEtherHdr);
	SET_AVBTP_VID(pEtherHdr, vlan);

	return;
}

