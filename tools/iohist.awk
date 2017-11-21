#!/usr/bin/ksh
# 
# This combo ksh/awk script can function in one of two ways.
# It can either be run live on a cluster or with user supplied
# input file(s). If user suppplied file(s) are usedi, they must 
# contain outpu from the "mmfsadm dump iohist" and "mmfsadm 
# dump stripe" commands.  I say file(s) because one file 
# containing both outputs would work as well as two seperate
# ones. Output will look similar to the following ..
#
#                         Num of   Time in      NSD      FS
# Time     R/W   Buf type sectors   seconds     name    name    K/sec  type Server(if cli)
# -------- ---   -------- ------- --------- -------- ------- ---------  ---- --------------
#
# 16:59:50   W    logData      18 0.0103100 gpfs1nsd   gpfs1    872.94  lcl
# 16:59:50   R   indBlock      16 0.0123800 gpfs1nsd   gpfs1    646.20  lcl
#
# This can be used in performance problems to see on a real 
# time basis what the latest (default is 1000) IO's are.
#
# Changes:
# 10/03/12  Created changes :-)
# 10/04/12  Fixed multi-dim arrays, added "header" and "lines" to control
#           if headers are reprinted (header=1) and how often (defaults to
#           every 24 lines (lines=xx).  These are passed on the command line.
#           
#           Also added variables and counters for possible per NSD summary.
# 08/22/13  Fix bug found input is multiple files.  Problem was that 
#           wrong node prefaced thre lines because of bad logic printing 
#           out the header.  Added previous_node variable  and initialize
#           node and previous_node in BEGIN.

function help { 
  
  clear
  echo "Syntax:";echo
  echo "  iohist.awk [[header=1,default=0] [lines=xx,default=24] [slowio=.xxx,default=none] slowdata=xxxx,default=none]] internaldump(s)" 
  echo ""
  echo "  where:"
  echo "    header ........... Headers are only printed once (default=0). If header=1"
  echo "                       specified, then header will be repeated every 24 lines"
  echo "                       unless lines=<some#> is used and then the header will"
  echo "                       be printed every "some#" of lines."
  echo ""
  echo "    internaldump(s) .. This can be either a full internaldump (dump all/"
  echo "                       saferdump all) or one or more files that contain at "
  echo "                       least 'dump iohist' and 'dump stripe'"
  echo ""
  exit
}

continue=0
debug=1

parms=$1
shift

if [[ -z $@ ]]
then
   live=1 
   /usr/lpp/mmfs/bin/mmfsadm dump iohist > /tmp/iohist.temp.out
   /usr/lpp/mmfs/bin/mmfsadm dump stripe > /tmp/stripe.temp.out
   /usr/lpp/mmfs/bin/mmfsadm dump disk > /tmp/disk.temp.out
   files="$parms /tmp/stripe.temp.out /tmp/disk.temp.out /tmp/iohist.temp.out"
   continue=1
else
  live=0
  files=$parms" "$@
  if [[ files == "" ]]
  then 
    help
  else
    echo "Files: "$files
  fi
fi     

awk  '
   BEGIN {
     DEBUG=0
     foundStripe=0
     foundDisk = 0
     foundIO = 0
     foundToken = 0
     skipiohistheader=0
     printHeader=1
     printCount=0
     lines=24
     header=0
     slowio=999999
     slowdata=0
     mfname=1
     mfname=1
     newVersion=0
     summary=0
     previous_node=""
  }
function iohist (ioh,UID) {  
  # I/O start time RW    Buf type disk:sectorNum     nSec  time ms      tag1      tag2           Disk UID typ      NSD server context   thread
  # --------------- -- ----------- ----------------- -----  ------- --------- --------- ------------------ --- --------------- --------- ----------
  # 10:53:32.134141  R    diskDesc   -1:4090             8    0.442        -1         0  0A856498:505C3670 lcl                 Unknown   PaxosChallengeThread
  # 10:53:33.891695  W       inode    5:35366492         1    0.340         0    137820  0A856478:4F07A6B7 lcl                 Revoke    InodeRevokeWorkerThread
  # 16:51:20.501776  W       inode   14:14319698         1    0,207         0   6704210  AC1E0003:506370C1 lcl                 NSDWorker NSDThread

  ret=0
  if ( ioh[1] != "" && ioh[9] != "00000000:00000000" && ioh[6] != 0 ) { 
    time=substr(ioh[1],1,8)
    Kbytes=(ioh[5]* 512)/1024
    if (index(ioh[6],"," ) > 0) {
      gsub(/\,/,".",ioh[6])
    }
    secs=ioh[6]/1000
    #print "time",time,"Kbytes",Kbytes,"secs",secs
    K=Kbytes/(ioh[6]/1000)
    UID[$9",totalsecs"]=UID[$9",totalsecs"]+secs
    UID[$9",totalKbytes"]=UID[$9",totalKbytes"]+Kbytes
    #print "totalsecs=",UID[$9",totalsecs"],"totalKbytes="UID[$9",totalKbytes"]
    if ( slowio == 999999 && slowdata == 0 ) {
      ret=1
    }
    if ( (slowio != 999999 && secs > slowio) || (slowdata !=0 && K < slowdata) ) {
      ret=1
    }
  } else {}
  return ret
}

function disk (line) {
  #State of Disk back01gpfsnode07 (devId FFFFFFFF devType Z devSubT N):
  #Size is 9223372036854775807 (0x7FFFFFFFFFFFFFFF) sectors
  #Unique ID is 0A0A27AB:53D51CA1

  dnsd=$4
  getline;getline
  duid=$4
  if (/Unique ID is/ && duid !=  NSD[dnsd",uid"] ) {
    olduid=NSD[dnsd",uid"]
    UID[duid",fs"]=UID[olduid",fs"]
    UID[duid",nsd"]="*"dnsd"*"
    if (DEBUG > 0 ) {print "disk:",dnsd,"Changed UID","From=",NSD[dnsd",uid"],"To=",duid}
    if (mnname < length(UID[duid",nsd"])) mnname = length(UID[duid",nsd"])
  }
  
}
function stripe (line) {
  #print "stripe="line
  if (index(line,"State of StripeGroup")> 0)
  {
    # Associate the filesystem unique id with filesystem name
    # State of StripeGroup "u" at 0xF1000004D0C0A000, uid 82B7A00D:483FE5ED, local id 1:
    fsName=$4
    if (mfname < length($4)) mfname = length($4)
    gsub(/\"/,"",fsName)
  }
  #        1: NULL: uid 09722341:48299F06, status NotInUse, availability Unavailable,
  #        1: ds0115a1P3S: uid 82B7A00D:483FE5BA, status InUse, availability OK,
  #if (line ~ /[0-9]:*.: uid/ && $2 != "NULL:"){
  if (line ~ /[0-9]:[ _0-9a-zA-z]*.: uid/ && $2 != "NULL:"){
    sub(/,/,"",$4)
    sub (/:/,"",$2)
    NSD[$2",uid"]=$4
    UID[$4",nsd"]=$2 
    UID[$4",fs"]=fsName
    if ( DEBUG ) { print "stripe: fs=",fsName,"uid",$4,"fsName=",UID[$4",fs"],"nsd=",UID[$4",nsd"],"uid=",NSD[$2",uid"] }
    if (mnname < length($2)) mnname = length($2)
  } 
}

function printit () {
  mnh=substr("-------------------------------",1,mnname)
  mfh=substr("-------------------------------",1,mfname)
  #print "filename",FILENAME,"pc",printCount,"l",lines,"pH",printHeader
  if (printHeader == 0 && printCount >= lines ) {printHeader=1}
  if (FILENAME != "mmfsadm_dump_some" ) {
    node=substr(FILENAME,1,index(FILENAME,"_")-1)
    if ( node == "" ) {node=FILENAME}
    if ( previous_node == "" || previous_node != node ) {
      previous_node=node
      outnode=node": "
      #printf ("\n%s\n\n",node)
      #printHeader=1
    }
  } else {
    outnode=""
  }
  if (printHeader) {
    printf("%s%+31s %+10s %"mnname"s %"mfname"s \n",outnode,"Num of","Time in","NSD","FS")
    printf("%s%-8s %+3s %+10s %+7s %+10s %"mnname"s %"mfname"s %9s %5s %15s",outnode,"Time","R/W","Buf type","sectors","seconds","name","name","K/sec","type","NSD server")
    if (newVersion == 1) {printf("%10s %24s","Context","Thread")} 
    printf("\n")
    printf("%s%8s %+3s %+10s %+7s %+10s %"mnname"s %-"mfname"s %9s %5s %15s",outnode,"--------","---","--------","-------","---------",mnh,mfh,"---------","----","--------------")
    if (newVersion == 1) {printf("%10s %9s","---------","------------------------")}
    printf("\n")
    printHeader=0
    printCount=3
  }
  #printf("%8s %3s %+10s %+7s %9.7f %+"mnname"s %8.2f %4s %12s\n",time,ioh[2],ioh[3],ioh[5],secs,UID[ioh[9]",nsd"],K,ioh[10],ioh[11])
  #printf("%8s %3s %+10s %+7s %9.7f %+"mnname"s %"mfname"s %9.2f %4s %12s",time,ioh[2],ioh[3],ioh[5],secs,UID[ioh[9]",nsd"],UID[ioh[9]",fs"],K,ioh[10],ioh[11])
  if (newVersion == 1 && (ioh[10] == "lcl" || ioh[10] == "srv") && num_of_ioh_fields == 12 ) {
    server="";context=ioh[11];thread=ioh[12]
  } else if (newVersion == 1 && (ioh[10] == "lcl" || ioh[10] == "srv") && num_of_ioh_fields == 13 ) {
    server=ioh[11];context=ioh[12];thread=ioh[13]
  } else if (newVersion == 1 && ioh[10] == "cli" ) {
    server=ioh[11];context=ioh[12];thread=ioh[13]
  } else {server=ioh[11];context="";thread=""}
    
#print "9",ioh[9]
  printf("%s%8s %3s %+10s %+7s %10.7f %+"mnname"s %"mfname"s %9.2f %4s %15s %10s %9s\n",outnode,time,ioh[2],ioh[3],ioh[5],secs,UID[ioh[9]",nsd"],UID[ioh[9]",fs"],K,ioh[10],server,context,thread)
  printCount++

}
 
# Main MAIN main AWK body 
{
  num_of_ioh_fields=split($0,ioh)
  # We could be looking at one file "dump all" and we need to extract
  # dump iohist and dump disk from that or seperate files that contain
  # each of these outputs which do not have ==== dump headers

  if ( index($0,"dump stripe") > 0 || index($0,"State of StripeGroup") > 0) { 
    if (DEBUG > 0 ) { print "Found dump stripe",$0 }
    if ( index($0,"dump stripe") > 0) { getline;getline }
    foundStripe=1
 
  }
  if ( index($0,"mmfsadm dump disk") > 0 || index($0,"===== dump disk =====") > 0 ) {
    foundDisk=1
    foundStripe=0
    if (DEBUG > 0 ) { print "Found dump disk",$0 }
    getline
  }
  if (index($0,"I/O history:") > 0) { 
    if (DEBUG > 0 ) { print "Found dump iohist",$0 }
    # This is the old verions
    #I/O history:
    #
    #I/O start time RW    Buf type disk:sectorNum     nSec  time ms      tag1      tag2           Disk UID typ      NSD server
    #--------------- -- ----------- ----------------- -----  ------- --------- --------- ------------------ --- ---------------

    # This is the new version (two extra field)
    #I/O history:
    #
    # I/O start time RW    Buf type disk:sectorNum     nSec  time ms      tag1      tag2           Disk UID typ      NSD server context   thread
    # --------------- -- ----------- ----------------- -----  ------- --------- --------- ------------------ --- --------------- --------- ----------
    # 10:53:32.134141  R    diskDesc   -1:4090             8    0.442        -1         0  0A856498:505C3670 lcl                 Unknown   PaxosChallengeThread
    # 10:53:33.891695  W       inode    5:35366492         1    0.340         0    137820  0A856478:4F07A6B7 lcl                 Revoke    InodeRevokeWorkerThread

    # Get past the headers
    #if ( index($0,"dump iohist") > 0 ) { getline;print "g1="$0;getline;print "g2="$0;getline;print "g3="$0;getline;print "g4="$0;getline}
    if ( index($0,"I/O history:") > 0 ) { 
      getline;getline
    }
    if ( index($0,"context   thread") > 0 ) { newVersion=1}
    getline
    foundIO=1
    foundDisk=0
    next
  }
    
  if ( foundIO == 1) {

    if ( index($0," dump ") > 0 ) { 
      foundIO=0
      #exit
      next
    } else {
      #15:14:17.381163  R   diskDesc    3:1             1   16.00        -1         0  00000000:00000000 cli   172.30.110.14
      # new twist, (the comman in the duration field)  
      #16:51:20.501776  W       inode   14:14319698         1    0,207         0   6704210  AC1E0003:506370C1 lcl                 NSDWorker NSDThread
      
      if ( DEBUG > 5 ) {print "main:","current", $0}
      
      rc=iohist(ioh,UID)
      if (rc) {
        # Add counter to print header every 48 lines or so.        
        printit()
      }
    }  
  } 
  if ( foundStripe == 1 ) {
    if ( index($0,"===== dump ") > 0  || index($0,"mmfsadm dump ")) { 
      foundStripe=0
      next
    } else {
      stripe($0)
    }
  } 
  if ( foundDisk == 1 ) {
    if ( index($0,"===== dump ") > 0 || index($0,"mmfsadm dump ") > 0) {
      foundDisk=0
      next
    } else {
       if ( index($0,"State of Disk") > 0 ) { 
         disk($0)
       }
    }

  }
}'  $files

if [[ $live = 1 ]]
then 
  rm /tmp/iohist.temp.out  
  rm /tmp/stripe.temp.out
  rm /tmp/disk.temp.out  
fi
