Motivation
==========

The Puppet agent can be a little unwieldy at times, for example when you want to
keep the agent disabled while debugging, but still want to do the occasional
manual run, e.g. to check what Puppet would change if enabled.

Doing that usually involves commandlines like this:

    puppet agent --enable; puppet agent --test --noop; puppet agent --disable 'my reason'

or like this:

    puppet agent --enable; puppet agent --test --tags ssh,rsyslog; puppet agent --disable 'my reason'

Since I have to do the above more or less frequently I wanted a more convenient
way of running those commands, so I cobbled together a small wrapper script for
my usual workflows.

Prerequisites
=============

The script requires that the Puppet client and [`jq`][1] are installed and in
the `$PATH`.

Installation
============

Download `pat`, put it somewhere in your `$PATH` and make it executable.

Usage
=====

    Wrapper for the Puppet agent to provide a more convenient way of invoking
    frequently used agent operations like enabling/disabling the agent or doing
    dry-runs.

    Usage: pat [-n] [-f] [-v] [-t TIME] [-E ENV] [TAG ...]
           pat -d [-f] [-u NAME] [REASON]
           pat -e [-r] [-t TIME] [-E ENV]
           pat -s
           pat -h

           -h       Print this help.

           -d       Disable the Puppet agent.
           -e       Enable the Puppet agent.
           -E ENV   Use the given Puppet environment (optional).
           -f       Force agent run when the agent is disabled or force replacement
                    of an already existing disable reason.
           -n       Do a dry-run (noop).
           -r       Run agent after enabling it.
           -s       Show agent status.
           -t TIME  Agent timeout in seconds (optional). Abort Puppet agent run if
                    it doesn't finish within the given time frame.
           -u NAME  Name to display along with disable reason. The parameter is
                    mandatory unless the environment variable ADMIN_NAME is defined.
                    If both the parameter and the environment variable are set, the
                    parameter value takes precedence.
           -v       Verbose mode (run agent with --debug).

    Without parameters a regular Puppet agent run is performed (puppet agent --test).

    If the agent is disabled, it will be temporarily re-enabled for a dry-run or a
    forced (live) run, and then disabled again with the same reason as before.

    Disabling the agent also disables the Puppet agent cron job. Enabling the agent
    restores a disabled Puppet agent cron job.

Notes
=====

At my workplace we're using cron for scheduled Puppet runs, therefore the script
disables this cron job (`/etc/cron.d/puppet`) when disabling the agent, and
restores it when re-enabling the agent. If you don't do scheduled Puppet runs
you can use the script as-is (a missing cron job will simply be ignored). But if
you use a different cron job or an entirely different method of scheduling
Puppet runs you'll have to modify the function `scheduled_runs()` accordingly.

The script also assumes that the Puppet client is installed in
`/opt/puppetlabs`. If you installed it in a different location you need to
modify the paths at the top of the script accordingly.

License
=======

This script is free software licensed under the [GNU General Public License
version 3.0][2] (see [LICENSE][3]).

`SPDX-License-Identifier: GPL-3.0-or-later`

[1]: https://stedolan.github.io/jq/
[2]: https://www.gnu.org/licenses/gpl-3.0.en.html
[3]: /LICENSE
