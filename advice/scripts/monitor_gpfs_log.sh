#!/usr/bin/ksh
#  script to monitor for Connection timed out messages in the /var/adm/ras/mmfs.log.latest file
#  and call missedpingexit for the other node

# Second to sleep between checking -  we usually have a minute before expel.
secondsToSleep=20

# mmfs log file to monitor
logToGrep=/var/adm/ras/mmfs.log.latest
#logToGrep=./mmfs.log.latest

# Trip file.  Will exist if trap is sprung  -  so we only capture data once
trapHasSprung=/tmp/mmfs/NoRouteSprung

extra_file=/tmp/mmfs/no_route_host.extra
#trapHasSprung=./NoRouteSprung

# message to trap on
trapMessage="No route to host"

rm $trapHasSprung 2>/dev/null

# Initial count of connection timed out messages in mmfs log
baseCount=$(grep "$trapMessage" $logToGrep | wc -l)

# do this loop while the trip file does not exist
echo "Start to monitor New logText: $trapMessage in $logToGrep"

while [[ ! -f $trapHasSprung ]]
do
  sleep $secondsToSleep

  # Get current count of expelled to check against the initial.
  currentCount=$(grep "$trapMessage" $logToGrep | wc -l)

  if [[ $currentCount > $baseCount ]]
  then
    # Get the entry that tripped this trap
    # Wed Apr  9 03:38:07.361 2014: Close connection to 192.168.1.29 testnode29 <c0n29> (Connection timed out)
    set -A expired $(grep "$trapMessage" $logToGrep | tail -1)

    # Get the IP and hostname of expelled node. Values are one less than might
    # be expected due to indexing starting at zero.
    hostname=${expired[6]}
    echo "$trapMessage occurred, hostname is: $hostname"

    echo "start to run following cmd:"

    curDate=$(date +"%m%d%H%M%S")
    echo "/usr/lpp/mmfs/bin/mmfsadm dump all > /tmp/mmfs/no_route_host.dumpall.$curDate"
    /usr/lpp/mmfs/bin/mmfsadm dump all > /tmp/mmfs/no_route_host.dumpall.$curDate

    curDate=$(date +"%m%d%H%M%S")
    echo "/usr/lpp/mmfs/bin/mmdsh -N $hostname '/usr/lpp/mmfs/bin/mmfsadm dump all > /tmp/mmfs/no_route_host.dumpall.$curDate'"
    /usr/lpp/mmfs/bin/mmdsh -N $hostname "/usr/lpp/mmfs/bin/mmfsadm dump all > /tmp/mmfs/no_route_host.dumpall.$curDate"

    echo "Collecting more network info to file:$extra_file"
    echo "== ping status ==" >> $extra_file
    ping -c 6 $hostname >> $extra_file

    echo "== nc -zv $hostname 1191" >> $extra_file
    nc -zv $hostname 1191 >> $extra_file

    echo "== arp -a ==" >> $extra_file
    arp -a >> $extra_file
    echo "== netstat -ano ==" >> $extra_file
    netstat -ano >> $extra_file
    echo "== ifconfig -a ==" >> $extra_file
    ifconfig -a >> $extra_file

    tripLine="$(date) $hostname"
    echo $tripLine  >  $trapHasSprung
  else
    echo "currentCount: $currentCount, baseCount: $baseCount, not new logText hit:$trapMessage, waiting for another $secondsToSleep seconds"
  fi

done