#!/usr/bin/env python
import xmostest

def runtest():
    testlevel = 'smoke'
    resources = xmostest.request_resource('xsim')

    binary = 'dbc_timestamp_valid/bin/dbc_timestamp_valid.xe'.format()
    tester = xmostest.ComparisonTester(open('dbc_timestamp_valid.expect'),
                                       'lib_tsn',
                                       'lib_tsn_tests',
                                       'dbc_timestamp_valid',
                                       {})
    tester.set_min_testlevel(testlevel)
    xmostest.run_on_simulator(resources['xsim'], binary, simargs=[], tester=tester)
