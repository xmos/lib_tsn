// Copyright (c) 2015, XMOS Ltd, All rights reserved
#ifndef _xc2compat_h_
#define _xc2compat_h_

#ifdef __XC__
#define unsafe unsafe
#else
#define unsafe
#endif

#ifdef __XC__
#define alias alias
#else
#define alias
#endif

#endif
