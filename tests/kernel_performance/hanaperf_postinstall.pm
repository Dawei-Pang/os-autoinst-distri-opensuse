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

    select_console 'sol', await_console => 0;
    assert_screen('linux-login', 1800);
    select_serial_terminal();

    assert_script_run 'nmcli connection show';
    assert_script_run 'rm -f /etc/NetworkManager/system-connections/default_connection.nmconnection';
    assert_script_run 'echo -e "[main]\nno-auto-default=type:ethernet" > /etc/NetworkManager/conf.d/disable_auto.conf';
    assert_script_run 'systemctl restart NetworkManager';
    assert_script_run 'nmcli networking off';
    assert_script_run 'nmcli networking on';
    assert_script_run 'nmcli connection add type ethernet con-name "nic0" ifname "*" mac '.get_var("HANA_PERF_OS_NIC");
    assert_script_run 'nmcli connection show';
}
1;
