#!/usr/bin/env python
import xmostest

if __name__ == '__main__':
    xmostest.init()
    xmostest.register_group('lib_tsn',
                            'lib_tsn_tests',
                            'TSN library tests',
    '''
TSN library tests
''')
    xmostest.runtests()
    xmostest.finish()
