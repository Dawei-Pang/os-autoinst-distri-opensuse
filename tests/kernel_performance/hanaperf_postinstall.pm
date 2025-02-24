# SUSE's openQA tests
#
# Copyright 2018 SUSE LLC
# SPDX-License-Identifier: FSFAP
#
# Summary: setup performance run environment
# Maintainer: Joyce Na <jna@suse.de>

use base 'y2_installbase';
use strict;
use warnings;
use utils;
use testapi;
use serial_terminal 'select_serial_terminal';

sub run {
    my $self = shift;

    select_serial_terminal;

    assert_script_run 'nmcli connection show';


}
1;
