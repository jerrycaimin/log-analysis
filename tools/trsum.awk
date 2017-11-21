#!/bin/awk -f
# You need a formatted trace file to analyze with this script first.
# Turn on trace :  mmtrace trace={io | def | all}  
# Stop trace and format the file : mmtrace stop
BEGIN {
  if (ARGC < 2)
  {
    print "Usage: trsum.awk "
    print "       [traceBR=1] [traceTok=1] [traceNew=1] [traceCond=1]"
    print "       [traceMutex=1] [mutexDetails=1] [traceFetch=1]"
    print "       [traceIO=0] [traceMsg=0] [IOhist=0] [details=0]"
    print "       [tidcol=n] [timecol=m] [tickfactor=24] [addtime=secs]"
    print "       trcfile [trcfile2 ...]"
    terminate=1
    exit 1
  }
#  Default settings
  details=1
  traceIO=1
  traceMsg=1
  IOhist=1
  lockhist=1
  tidcol = 5
  timecol = 14
  tickfactor = 1
  lockbucketsize = 0.0005
  reqbucketsize = 0.0005
  iobucketsize = 0.0005
  sendbucketsize = 0.0001
  handbucketsize = 0.0001
  timebucketsize = 1.0
  minlockbucket = 999999
  minreqbucket = 999999
  miniobucket = 999999
  mintimebucket = 999999

  newtid=-1
  hex[0]="0"; hex[1]="1"; hex[2]="2"; hex[3]="3"
  hex[4]="4"; hex[5]="5"; hex[6]="6"; hex[7]="7"
  hex[8]="8"; hex[9]="9"; hex[10]="A"; hex[11]="B"
  hex[12]="C"; hex[13]="D"; hex[14]="E"; hex[15]="F"
}

function d2x(dec, cnt, ch, i, val) # change decimal to hex
{
  ch = ""
  for (i=1 ; i<=cnt ; i++)
  {
    val = dec%16
    dec=(dec-val)/16
    ch = hex[val] ch
  }
  return ch
}

function stuffafter(haystack, needle, pos) #find a particular string if it exists
{
  pos = index(haystack, needle)
  if (pos > 0)
    return substr(haystack, pos+length(needle))
  return ""
}

function wordbefore(haystack, needle, pos, endpos) #return the string before a particular string if it exists
{
  endpos = index(haystack, needle)
  if (endpos <= 1)
    return ""
  for (pos = endpos-1; pos >= 1; pos--)
    if (substr(haystack,pos,1) != " ") break
  endpos = pos + 1
  for (pos = endpos-1; pos >= 1; pos--)
    if (substr(haystack,pos,1) == " ") break
  return substr(haystack, pos+1, endpos-pos)
}

function lastpos(haystack, needle, pos)  # return the position of a particular string if it exists
{
  for (pos = length(haystack); pos > 0 ; pos--)
    if (substr(haystack,pos,1) == needle) return pos
  return pos
}

function firstword(line, pos)  #return first string
{
  pos = index(line, " ")
  while (pos == 1)
  {
    line = substr(line,2)
    pos = index(line, " ")
  }
  if (pos > 0)
    return substr(line, 1, pos-1)
  return line
}

function x2d(hex, d, ch, i, val) #convert hex to decimal
{
  d = 0
  for (i=1 ; i<=length(hex) ; i++)
  {
    ch = substr(hex,i,1)
    val = index("0123456789ABCDEF", ch)
    if (val == 0)
      val = index("0123456789abcdef", ch)
    d = d*16 + val - 1
  }
  return sprintf("%d",d)
}

function getmutextype(pos, ret)
{
  ret=$pos
  if (substr(ret,2,2) == "0x")
  {
    pos++
    ret=$pos
  }
  while (pos <= NF && substr($pos,length($pos)) != ")")
  {
    pos++
    ret=ret" "$pos
  }
  return ret
}

#Linux:
#tracereport entrys
#
#           Date              Pid  COMPONENT_TAG: application trace record
#---------- -------------------------- ------ ---------------------------------------
#Thu Apr 19 12:53:46 2012.796419  14390 TRACE_FS: DIRTYBIT_DEBUG traceDumpDirtyBits: ino 74763 blkNum 990 validBits 0x0-0-0-0

# Timestamp    Pid  COMPONENT_TAG: application trace record
#----------- ------ ---------------------------------------
#   0.000000   1302 TRACE_VNODE: cxiSleep: end delay 1000 HZ 100

#    Timestamp      Pid  P B Hookword COMPONENT_TAG: application trace record
#---------------- ------ - - -------- ---------------------------------------
#        0.000000   1302 1 3     2642 TRACE_VNODE: cxiSleep: end delay 1000 HZ 100
/COMPONENT_TAG: application trace record/ {
  cpucol = 0
  if (index($0,"           Date ") > 0)
  {
    tidcol = index($0,"  Pid ")+5
    timecol = -1
    convertDate = 1
    if (index($0," P ") > 0) cpucol = tidcol+7
  }
  else
  {
    if (index($0,"  Pid ") > 0)
    {
      tidcol = index($0,"  Pid ")
      timecol = index($0,"    Timestamp ")
      print "timecol-comp0",timecol,"tidcol-comp0",tidcol
      if (timecol == 0) timecol = index($0,"  Timestamp ")
      else cpucol = index($0," P ")+1
      print "timecol-comp1",timecol,"tidcol-comp1",tidcol
    }
    else if (index($0,"  TID") > 0)
    {
      tidcol = index($0,"  TID")
      timecol = index($0,"Relative-seconds")
      print "timecol-comp2",timecol,"tidcol-comp2",tidcol
    }
  }
  lxtrace = 1
  getline  # toss next line
}

#AIX:
/APPL    SYSCALL KERNEL/ {
  cpucol = index($0,"CPU ")
  tidcol = index($0,"TID ")
  if (tidcol == 0) tidcol = index($0,"PID ")
  namecol = index($0,"PROCESS NAME ")
  timecol = index($0,"ELAPSED")-3
}

#Windows:
#Flg HH:MM:SS         Pid. Tid.C Thread Function:line                    Obj addr         Object name              Message
#--- --------        ----------- ------ -------------------------------- --------         -----------              -------
#    14:40:10.701431 C8BC0.6CAA0.2 K      TRACE_VNODE: gpfsNode_t::findOrCreate exit: err 0 code 0 gnP 0xFFFFFA80F2CE6870 vP 0xFFFFFA80F8723798 filesetid 0
#*** Missing 8 trace records ***
/Flg HH:MM:SS/ {
  wintrace = 1
  cpucol = 0
  tidcol = index($0," Pid ")
  timecol = index($0,"HH:MM:SS")
  lxtrace = 1
  getline  # toss next line
}

#006 1929377     7.160342830       0.000826                   TRACEBUFFER WRAPAROUND 5D88 C77A missed entries
#006
/TRACEBUFFER WRAPAROUND/ {
  if (tidcol > 0)
    newtid = firstword(substr($0, tidcol))
  else
    newtid = oldtid[newcpu]
  if (timecol > 0)
  {
    newtime = firstword(substr($0, timecol))
    if (addtime > 0) newtime += addtime
    if (tickfactor > 1 && newtime != "")
      newtime = newtime * tickfactor
  }
  if (index($0,"missed entries") > 0)
  {
    if (details)
      printf("%8d%s %17.9f MISSED %8d TRACES\n", newtid, cpusuff, newtime, x2d(substr($(NF-2),8)))
  }
}

# 101
/_exit LR / {
  if (tidcol > 0)
    newtid = firstword(substr($0, tidcol))
  else
    newtid = oldtid[newcpu]
  if (timecol > 0)
  {
    newtime = firstword(substr($0, timecol))
    if (addtime > 0) newtime += addtime
    if (tickfactor > 1 && newtime != "")
      newtime = newtime * tickfactor
  }
  if (details)
    printf("%8d%s %17.9f _exit\n", newtid, cpusuff, newtime)
}

# 4B0
/undispatch: / {next}

# 106
/dispatch: / {
  if (cpucol > 0)
  {
    if (tidcol > 0)
      newtid = firstword(substr($0, tidcol))
    else
      newtid = oldtid[newcpu]
    if (timecol > 0)
    {
      newtime = firstword(substr($0, timecol))
      if (addtime > 0) newtime += addtime
      if (tickfactor > 1 && newtime != "")
        newtime = newtime * tickfactor
    }

    rec = stuffafter($0, "dispatch: ")

    if (firstword(rec) == "scheduler") next

    if (firstword(rec) == "idle") newcmd = "idle"
    else if (firstword(rec) == "wait") newcmd = "idle"
    else newcmd = firstword(stuffafter(rec,"cmd="))
    xnewtid = firstword(stuffafter(rec," tid="))
    if (xnewtid != "?")
    {
      newtid=xnewtid
      usec=0
    }
    else
      usec=firstword(stuffafter(rec,"["))
    newcpu = firstword(stuffafter(rec,"CPUID="))
    cpusuff = sprintf(":%-2d", newcpu)
    if (numcpu < newcpu+1) numcpu = newcpu+1

    if (oldtid[newcpu] != 0) {
      delta = (newtime-oldtime[newcpu])*1000000   # usec
      idledelta = 0
      if (usec > 0 && delta > usec)
      {
        idledelta = delta - usec
        delta = usec
        str="---"
        totcpu[oldtid[newcpu]" "str] += idledelta/1000000
        if (details)
          printf("%8d%s %17.9f %-20s %12.3f us\n", oldtid[newcpu], cpusuff, newtime, str, idledelta)
      }
      if (namecol > 0 && oldcmd[newcpu] == "")
        oldcmd[newcpu] = firstword(substr($0, namecol, 6))
      if (oldcmd[newcpu] == "wait") str="---"
      else if (oldcmd[newcpu] == "idle") str="---"
      else str= "[" oldcmd[newcpu] "]"
      totcpu[oldtid[newcpu]" "str] += delta/1000000
      tidname[oldtid[newcpu]] = str
      if (details)
        printf("%8d%s %17.9f %-20s %12.3f us\n", oldtid[newcpu], cpusuff, newtime, str, delta)
    }
    oldtid[newcpu] = newtid
    oldcmd[newcpu] = newcmd
    oldtime[newcpu] = newtime
    oldcpu = newcpu
  }
}

# 102
/slih cpuid/ {
  if (cpucol > 0)
  {
    newcpu = firstword(substr($0, cpucol, 6))
    if (numcpu < newcpu+1) numcpu = newcpu+1
    cpusuff = sprintf(":%-2d", newcpu)
    if (tidcol > 0)
      newtid = firstword(substr($0, tidcol))
    else
      newtid = oldtid[newcpu]
    if (timecol > 0)
    {
      newtime = firstword(substr($0, timecol))
      if (addtime > 0) newtime += addtime
      if (tickfactor > 1 && newtime != "")
        newtime = newtime * tickfactor
    }

    rec = stuffafter($0, "slih cpuid=")
    newcmd = firstword(substr(rec,3))
    if (newcmd == "FFFFFF") newcmd = "idle"
    if (namecol > 0 && newcmd == "")
      newcmd = firstword(substr($0, namecol, 6))

    if (oldtid[newcpu] != 0) {
      delta = (newtime-oldtime[newcpu])*1000000
      if (namecol > 0 && oldcmd[newcpu] == "")
        oldcmd[newcpu] = firstword(substr($0, namecol, 6))
      if (oldcmd[newcpu] == "wait") str="---"
      else if (oldcmd[newcpu] == "idle") str="---"
      else str= "[" oldcmd[newcpu] "]"
      totcpu[oldtid[newcpu]" "str] += delta/1000000
      tidname[oldtid[newcpu]] = str
      if (details)
        printf("%8d%s %17.9f %-20s %12.3f us\n", oldtid[newcpu], cpusuff, newtime, str, delta)
    }
    slihresumes[newcpu] = oldcmd[newcpu]
    oldtid[newcpu] = newtid
    oldcmd[newcpu] = newcmd
    oldtime[newcpu] = newtime
    oldcpu = newcpu
  }
}

# 103
/return from slih/ {
  if (cpucol > 0)
  {
    newcpu = firstword(substr($0, cpucol, 6))
    if (numcpu < newcpu+1) numcpu = newcpu+1
    cpusuff = sprintf(":%-2d", newcpu)
    if (tidcol > 0)
      newtid = firstword(substr($0, tidcol))
    else
      newtid = oldtid[newcpu]
    if (timecol > 0)
    {
      newtime = firstword(substr($0, timecol))
      if (addtime > 0) newtime += addtime
      if (tickfactor > 1 && newtime != "")
        newtime = newtime * tickfactor
    }

    newcmd = slihresumes[newcpu]
    delete slihresumes[newcpu]
    if (namecol > 0 && newcmd == "")
      newcmd = firstword(substr($0, namecol, 6))

    if (oldtid[newcpu] != 0) {
      delta = (newtime-oldtime[newcpu])*1000000
      if (namecol > 0 && oldcmd[newcpu] == "")
        oldcmd[newcpu] = firstword(substr($0, namecol, 6))
      if (oldcmd[newcpu] == "wait") str="---"
      else if (oldcmd[newcpu] == "idle") str="---"
      else str= "[" oldcmd[newcpu] "]"
      totcpu[oldtid[newcpu]" "str] += delta/1000000
      tidname[oldtid[newcpu]] = str
      if (details)
        printf("%8d%s %17.9f %-20s %12.3f us\n", oldtid[newcpu], cpusuff, newtime, str, delta)
    }
    oldtid[newcpu] = newtid
    oldcmd[newcpu] = newcmd
    oldtime[newcpu] = newtime
    oldcpu = newcpu
  }
}

# 100
/INTERRUPT iar=/ {
  if (cpucol > 0)
  {
    newcpu = firstword(substr($0, cpucol, 6))
    if (numcpu < newcpu+1) numcpu = newcpu+1
    cpusuff = sprintf(":%-2d", newcpu)
    if (newcpu >= 0)
    {
      if (tidcol > 0)
        newtid = firstword(substr($0, tidcol))
      else
        newtid = oldtid[newcpu]
      if (timecol > 0)
      {
        newtime = firstword(substr($0, timecol))
        if (addtime > 0) newtime += addtime
        if (tickfactor > 1 && newtime != "")
          newtime = newtime * tickfactor
      }

      newcmd = wordbefore($0, " INTERRUPT iar=") "INTERRUPT"
      if (newcmd == "DECREMENTER") newcmd = "DECR"

      if (oldtid[newcpu] != 0) {
        delta = (newtime-oldtime[newcpu])*1000000
        if (namecol > 0 && oldcmd[newcpu] == "")
          oldcmd[newcpu] = firstword(substr($0, namecol, 6))
        if (oldcmd[newcpu] == "wait") str="---"
        else if (oldcmd[newcpu] == "idle") str="---"
        else str= "[" oldcmd[newcpu] "]"
        totcpu[oldtid[newcpu]" "str] += delta/1000000
        tidname[oldtid[newcpu]] = str
        if (details)
          printf("%8d%s %17.9f %-20s %12.3f us\n", oldtid[newcpu], cpusuff, newtime, str, delta)
      }
      oldtid[newcpu] = newtid
      oldcmd[newcpu] = newcmd
      oldtime[newcpu] = newtime
      oldcpu = newcpu
    }
  }
}

# 200
/resume/ {
  if (cpucol > 0)
  {
    newcpu = firstword(substr($0, cpucol, 6))
    if (numcpu < newcpu+1) numcpu = newcpu+1
    cpusuff = sprintf(":%-2d", newcpu)
    if (tidcol > 0)
      newtid = firstword(substr($0, tidcol))
    else
      newtid = oldtid[newcpu]
    if (timecol > 0)
    {
      newtime = firstword(substr($0, timecol))
      if (addtime > 0) newtime += addtime
      if (tickfactor > 1 && newtime != "")
        newtime = newtime * tickfactor
    }

    newcmd = firstword(stuffafter($0, "resume "))
    if (newcmd == "wait") newcmd = "idle"

    if (oldtid[newcpu] != 0) {
      delta = (newtime-oldtime[newcpu])*1000000
      if (namecol > 0 && oldcmd[newcpu] == "")
        oldcmd[newcpu] = firstword(substr($0, namecol, 6))
      if (oldcmd[newcpu] == "wait") str="---"
      else if (oldcmd[newcpu] == "idle") str="---"
      else str= "[" oldcmd[newcpu] "]"
      totcpu[oldtid[newcpu]" "str] += delta/1000000
      tidname[oldtid[newcpu]] = str
      if (details)
        printf("%8d%s %17.9f %-20s %12.3f us\n", oldtid[newcpu], cpusuff, newtime, str, delta)
    }
    oldtid[newcpu] = newtid
    oldcmd[newcpu] = newcmd
    oldtime[newcpu] = newtime
    oldcpu = newcpu
  }
}

# 60A
/HKWD_LIBC_MALLOC_SUBSYSTEM/ {
  if (traceNew)
  {
    recrest = stuffafter($0, "HKWD_LIBC_MALLOC_SUBSYSTEM ")
    if (cpucol > 0)
    {
      newcpu = firstword(substr($0, cpucol, 6))
      if (numcpu < newcpu+1) numcpu = newcpu+1
      cpusuff = sprintf(":%-2d", newcpu)
    }
    if (tidcol > 0)
      newtid = firstword(substr($0, tidcol))
    else
      newtid = oldtid[newcpu]
    if (timecol > 0)
    {
      newtime = firstword(substr($0, timecol))
      if (addtime > 0) newtime += addtime
      if (tickfactor > 1 && newtime != "")
        newtime = newtime * tickfactor
    }

    if (index(recrest, "function=malloc") > 0)
    {
      rest = stuffafter(recrest, "size=")
      bytes = firstword(rest)
      rest = stuffafter(rest, "retval=")
      bytesat = firstword(rest)
      if (allocatedseenM[bytesat] == "")
      {
        allocatedseenM[bytesat] = 1
        allocatedlistM[allocatedctr] = bytesat
        allocatedctrM++
      }
      allocatedbyM[bytesat] = newtid
      allocatedtimeM[bytesat] = newtime
      allocatedbytesM[bytesat] = bytes
      allocatedtypeM[bytesat] = "malloc"
      allocatesM++
    }
    else if (index(recrest, "function=free") > 0)
    {
      rest = stuffafter(recrest, "ptr=")
      bytesat = firstword(rest)
      allocatedbyM[bytesat] = ""
      freesM++
    }
  }
}

# 306,307,308,309
/MMFS | TRACE_/ {
  rec = $0
  trinx = index($0," TRACE_")
  if (trinx > 0)
  {
    recrest = substr($0,trinx+7)
    lxtrace=1
    if (wintrace)
    {
      #    13:01:34.136354 121DDC.25DBF8.4 K      TRACE_...
      timecol = index($0,$1)
      tidcol = index($0,$2)
      cpucol = tidcol
    }
    else # Linux
    {
      if (tidcol == 0) tidcol = trinx - 6
      if (timecol == 0)
      {
        timecol = tidcol - 12
        if (timecol <= 0) timecol = 1
      }
    }
  }
  else
    recrest = stuffafter($0, "MMFS ")
  if (cpucol > 0)
  {
    newcpu = firstword(substr($0, cpucol))
    if (wintrace)
    {
      # 121DDC.25DBF8.4   Pid.Tid.C
      split(newcpu,temp,"[.]")
      newcpu = x2d(temp[3])
    }
    if (numcpu < newcpu+1) numcpu = newcpu+1
    cpusuff = sprintf(":%-2d", newcpu)
  }
  else
  {
    newcpu = oldcpu
    cpusuff = ""
  }
  if (tidcol > 0)
  {
    newtid = firstword(substr($0, tidcol))
    if (wintrace)
    {
      # 121DDC.25DBF8.4   Pid.Tid.C
      split(newtid,temp,"[.]")
      newtid = x2d(temp[2])
    }
  }
  else
    newtid = oldtid[newcpu]
  if (timecol > 0)
  {
    newtime = firstword(substr($0, timecol))
    if (wintrace)
    {
      # 14:40:10.701431
      fields=split(newtime,HMS,":")
      if (fields == 3)
      {
        pos=index(HMS[3],".")
        holdtime = ntime
        ntime = sprintf("%0.6f",HMS[1]*3600 + HMS[2]*60 + HMS[3])
        if (firstConvert == "")
          firstConvert = ntime
        else
          if (ntime < holdtime) ntime += 24*3600 # must be a new day
        newtime = sprintf("%0.6f",ntime - firstConvert)
      }
    }
    if (addtime > 0) newtime += addtime
    if (tickfactor > 1 && newtime != "")
      newtime = newtime * tickfactor
  }
  else if (convertDate)
  {
    fields=split($4,HMS,":")
    if (fields == 3)
    {
      pos=index($5,".")
      if (pos > 0) subsec=substr($5,pos)
      else subsec=0
      holdtime = ntime
      ntime = sprintf("%0.6f",HMS[1]*3600 + HMS[2]*60 + HMS[3] + subsec)
      if (firstConvert == "")
        firstConvert = ntime
      else
        if (ntime < holdtime) ntime += 24*3600 # must be a new day
      newtime = sprintf("%0.6f",ntime - firstConvert)
    }
  }
  if (namecol > 0 && oldcmd[newcpu] == "")
    oldcmd[newcpu] = firstword(substr($0, namecol, 6))

  if (index(recrest, "ERRLOG") > 0)
  {
    rest=stuffafter(recrest, "ERRLOG: ")
    printf("%8d%s %17.9f ERRLOG: %s\n", newtid, cpusuff, newtime, rest)
  }
  else if (index(recrest, "VNODE: mmfs_") > 0 ||
           index(recrest, "VNODE: gpfs_v_") > 0 ||
           index(recrest, "VNODE: vnodeLockctlInternal") > 0 )
  {
    if (index(recrest, "VNODE: mmfs_") > 0)
    {
      # Parse Var recrest "mmfs_"req entexit rest
      rest=stuffafter(recrest, "mmfs_")
    }
    else if (index(recrest, "VNODE: gpfs_v_") > 0)
    {
      # Parse Var recrest "gpfs_v_"req entexit rest
      rest=stuffafter(recrest, "gpfs_v_")
    }
    else if (index(recrest, "VNODE: vnodeLockctlInternal") > 0)
      rest="lockctl" stuffafter(recrest, "vnodeLockctlInternal")
    treq=firstword(rest)
    rest=stuffafter(rest, treq)
    entexit=firstword(rest)
    rest=stuffafter(rest, entexit)
    for (i = 1; i <= tidcount; i++)
      if (tids[i] == newtid) break
    if (i > tidcount)
    {
      tids[i] = newtid
      tidcount = i
    }
    if (treq == "rele" || treq == hold) entexit = ""
    if (entexit == "enter:") {
      if (substr(treq,1,4) == "rdwr") {
        op = firstword(stuffafter(rest, " op "))
        if (op == "0") uioop[newtid] = "1"
        else if (op == "1") uioop[newtid] = "0"
        if (IOhist)
        {
          rdwrinprog++
          inpbucket[rdwrinprog]++
        }
      }
      if (treq == "lookup") extra = stuffafter(rest, " name ")
      else if (treq == "root")
      {
        # Parse Var rest extra " vPP "
        pos = index(rest, " vPP ")
        if (pos > 0) extra = substr(rest,1,pos-1)
        else extra = rest
      }
      else if (treq == "mkdir") extra = stuffafter(rest, " dirName ")
      else if (treq == "rmdir") extra = stuffafter(rest, " name ")
      else if (treq == "vget") extra = "inode "stuffafter(rest, " ino ")
      else if (treq == "rename") {
        if (substr(rest,1,1) == "v")
          extra = stuffafter(rest, " name ")
        else {
          extra = stuffafter(rest, " new name ")
          if (details)
            printf("%8d%s %17.9f rename to (%s) %s\n", newtid, cpusuff, newtime, oldcmd[newcpu], extra)
        }
      }
      else extra=""
      if (tlevel == 0)
      {
        if (firstVFStime == 0) firstVFStime = newtime
        if (idleVFSstart != 0)
        {
          idleVFS += newtime - idleVFSstart
          idleVFSstart = 0
        }
      }
      tlevel = tlevel + 1
      reqi = reqs[newtid]+1
      reqs[newtid] = reqi
      req[newtid,reqi] = treq
      time[newtid,reqi] = newtime
      level[newtid,reqi] = tlevel
      ruwaitStart[newtid] = 0
      if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
      else str=treq
      if (extra != "") str = str " " extra
      if (idlestart[newtid] != "") {
        idletime = newtime-idlestart[newtid]
        if (details)
          printf("%8d%s %17.9f %-33s ext %12.3f us\n", newtid, cpusuff, newtime, str, idletime*1000000)
      }
      else {
        if (details)
          printf("%8d%s %17.9f %s\n", newtid, cpusuff, newtime, str)
      }
      if (idlestart[newtid] != "") {
        timeout[newtid] += idletime
        idlestart[newtid] = ""
      }
    }

    else if (entexit == "exit:") {
      exrc = firstword(stuffafter(rest, " rc "))
      if (exrc == "0") exrc = ""
      else if (exrc == "2" && treq == "lookup") exrc = " NOTFOUND"
      else if (exrc == "25" && treq == "ioctl") exrc = " NOTTY"
      else if (treq == "getxattr" && exrc > 0) exrc = ""
      else if (exrc != "") exrc = " err="exrc
      for (wp = reqs[newtid]; wp >= 1; wp--)
        if (treq == req[newtid,wp])
          break;
      if (wp > 0) {
        oldtimex = time[newtid,wp]
        oldlevel = level[newtid,wp]
        for (; wp < reqs[newtid]; wp++)
        {
          req[newtid,wp] = req[newtid,wp+1]
          time[newtid,wp] = time[newtid,wp+1]
          level[newtid,wp] = level[newtid,wp+1]
        }
        reqs[newtid]--
        delta = (newtime-oldtimex)*1000000
        if (delta >= 1000) mark = " +"
        else mark = ""
        if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
        else str=treq
        if (details)
          printf("%8d%s %17.9f %-20s %12.3f us%s%s\n", newtid, cpusuff, newtime, str, delta, mark, exrc)
        if (tlevel <= 0)
        {
          idleVFS = 0
          firstVFStime = 0.000000001
        }
        if (tlevel >= oldlevel && oldlevel >= 1)
        {
          tlevel = oldlevel - 1
          if (tlevel <= 0)
            idleVFSstart = newtime
        }
        lastVFStime = newtime
        if (reqs[newtid] == 0) {
          timein[newtid] += newtime-oldtimex
          idlestart[newtid] = newtime
          tidopcnt[newtid]++
        }
        timeop[treq] += newtime-oldtimex
        cntop[treq]++
      }
      else if (treq != "hold") {
        if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
        else str=treq
        if (details)
          printf("%8d%s %17.9f %-20s*************%s\n", newtid, cpusuff, newtime, str, exrc)
        if (tlevel <= 0)
        {
          idleVFS = 0
          firstVFStime = 0.000000001
        }
        else
        {
          tlevel = tlevel - 1
          if (tlevel <= 0)
            idleVFSstart = newtime
        }
        lastVFStime = newtime
      }
      if (IOhist && wp > 0 && substr(treq,1,4) == "rdwr")
      {
        delta = delta/1000000
        totaldelta += delta
        totalrdwrs++
        if (rdwrinprog > maxrdwrinprog) maxrdwrinprog=rdwrinprog
        rdwrinprog--
        if (rdwrinprog < 0) rdwrinprog = 0
        bucket = int(delta / reqbucketsize)
        if (minreqbucket > bucket) minreqbucket = bucket
        if (maxreqbucket < bucket) maxreqbucket = bucket
        if (rdwrKey[newtid] == "WRITE:")
          wrbuckets[bucket]++
        else if (rdwrKey[newtid] == "READ:")
          rdbuckets[bucket]++
        else
          buckets[bucket]++
        if (rdwrLen[newtid] != "")
        {
          if (rdwrKey[newtid] == "WRITE:")
            wrbucketBytes[bucket] += rdwrLen[newtid]
          else if (rdwrKey[newtid] == "READ:")
            rdbucketBytes[bucket] += rdwrLen[newtid]
          timebuck=int(newtime/timebucketsize);
          if (rdwrKey[newtid] == "WRITE:")
            wrbytessum[timebuck]+=rdwrLen[newtid];
          else
            rdbytessum[timebuck]+=rdwrLen[newtid];
          if (mintimebucket > timebuck) mintimebucket=timebuck;
          if (highbuck < timebuck) highbuck=timebuck
          delete rdwrLen[newtid]
          delete rdwrKey[newtid]
        }
      }
      else if (lockhist && wp > 0 && treq == "lockctl")
      {
        delta = delta/1000000
        totallockdelta += delta
        totallockctls++
        bucket = int(delta / lockbucketsize)
        if (minlockbucket > bucket) minlockbucket = bucket
        if (maxlockbucket < bucket) maxlockbucket = bucket
        lockbuckets[bucket]++
      }
    }
    else if (index(recrest, "fastopen") > 0) {           # ????
      # Parse Var recrest "oiP" rest
      rest = stuffafter(recrest, "oiP")
      if (details)
        printf("%8d%s %17.9f Open  %s\n", newtid, cpusuff, newtime, rest)
    }
  }

  else if (index(recrest, "VNODE: gpfs_i_") > 0 ||
           index(recrest, "VNODE: gpfs_f_") > 0 ||
           index(recrest, "VNODE: gpfs_s_") > 0 ||
           index(recrest, "VNODE: gpfs_d_") > 0)
  {
    rest=stuffafter(recrest, "VNODE: gpfs_")
    if (substr(rest,1,1) != "d")
      rest=substr(rest, 3)
    treq=firstword(rest)
    rest=stuffafter(rest, treq)
    # hack: gpfs_i_lookup: new -> gpfs_i_lookup exit: new
    if (treq == "lookup:" && firstword(rest) == "new")
    {
      treq = "lookup"
      rest = "exit: " rest
    }
    entexit=firstword(rest)
    rest=stuffafter(rest, entexit)
    if (treq == "listxattr" && entexit == "error")
    {
      entexit=firstword(rest)
      rest=stuffafter(rest, entexit)
    }
    # hack: exit2: -> exit:
    if (entexit == "exit2:") entexit = "exit:"
    for (i = 1; i <= tidcount; i++)
      if (tids[i] == newtid) break
    if (i > tidcount)
    {
      tids[i] = newtid
      tidcount = i
    }
    if (treq == "rele" || treq == hold) entexit = ""
    if (entexit == "enter:") {
      if (substr(treq,1,4) == "rdwr") {
        op = firstword(stuffafter(rest, " op "))
        if (op == "0") uioop[newtid] = "1"
        else if (op == "1") uioop[newtid] = "0"
        if (IOhist)
        {
          rdwrinprog++
          inpbucket[rdwrinprog]++
        }
      }
      if (treq == "lookup") extra = stuffafter(rest, " name ")
      else if (treq == "mkdir") extra = stuffafter(rest, " name ")
      else if (treq == "rmdir") extra = stuffafter(rest, " name ")
      else if (treq == "rename") extra = stuffafter(rest, " name ")
      else extra=""
      if (tlevel == 0)
      {
        if (firstVFStime == 0) firstVFStime = newtime
        if (idleVFSstart != 0)
        {
          idleVFS += newtime - idleVFSstart
          idleVFSstart = 0
        }
      }
      tlevel = tlevel + 1
      reqi = reqs[newtid]+1
      reqs[newtid] = reqi
      req[newtid,reqi] = treq
      time[newtid,reqi] = newtime
      level[newtid,reqi] = tlevel
      if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
      else str=treq
      if (extra != "") str = str " " extra
      if (idlestart[newtid] != "") {
        idletime = newtime-idlestart[newtid]
        if (details)
          printf("%8d%s %17.9f %-33s ext %12.3f us\n", newtid, cpusuff, newtime, str, idletime*1000000)
      }
      else if (details)
        printf("%8d%s %17.9f %s\n", newtid, cpusuff, newtime, str)
      if (idlestart[newtid] != "") {
        timeout[newtid] += idletime
        idlestart[newtid] = ""
      }
    }

    else if (entexit == "exit:") {
      exrc = firstword(stuffafter(rest, " rc "))
      if (exrc == "0") exrc = ""
      else if (exrc == "2" && treq == "lookup") exrc = " NOTFOUND"
      else if (exrc == "25" && treq == "ioctl") exrc = " NOTTY"
      else if (treq == "llseek" && substr(exrc,1,2) == "0x") exrc = ""
      else if (exrc != "") exrc = " err="exrc
      if (treq == "rdwr" && exrc == "")
      {
        resid = firstword(stuffafter(rest, "resid "))
        if (resid != "" && resid != 0)
          exrc = " resid="resid
      }
      for (wp = reqs[newtid]; wp >= 1; wp--)
        if (treq == req[newtid,wp])
          break;
      if (wp > 0) {
        oldtimex = time[newtid,wp]
        oldlevel = level[newtid,wp]
        for (; wp < reqs[newtid]; wp++)
        {
          req[newtid,wp] = req[newtid,wp+1]
          time[newtid,wp] = time[newtid,wp+1]
          level[newtid,wp] = level[newtid,wp+1]
        }
        reqs[newtid]--
        delta = (newtime-oldtimex)*1000000
        if (delta >= 1000) mark = " +"
        else mark = ""
        if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
        else str=treq
        if (details)
          printf("%8d%s %17.9f %-20s %12.3f us%s%s\n", newtid, cpusuff, newtime, str, delta, mark, exrc)
        if (tlevel <= 0)
        {
          idleVFS = 0
          firstVFStime = 0.000000001
        }
        if (tlevel >= oldlevel && oldlevel >= 1)
        {
          tlevel = oldlevel - 1
          if (tlevel <= 0)
            idleVFSstart = newtime
        }
        lastVFStime = newtime
        if (reqs[newtid] == 0) {
          timein[newtid] += newtime-oldtimex
          idlestart[newtid] = newtime
          tidopcnt[newtid]++
        }
        timeop[treq] += newtime-oldtimex
        cntop[treq]++
      }
      else if (treq != "hold") {
        if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
        else str=treq
        if (details)
          printf("%8d%s %17.9f %-20s*************%s\n", newtid, cpusuff, newtime, str, exrc)
        if (tlevel <= 0)
        {
          idleVFS = 0
          firstVFStime = 0.000000001
        }
        else
        {
          tlevel = tlevel - 1
          if (tlevel <= 0)
            idleVFSstart = newtime
        }
        lastVFStime = newtime
      }
      if (IOhist && wp > 0 && substr(treq,1,4) == "rdwr")
      {
        delta = delta/1000000
        totaldelta += delta
        totalrdwrs++
        if (rdwrinprog > maxrdwrinprog) maxrdwrinprog=rdwrinprog
        rdwrinprog--
        if (rdwrinprog < 0) rdwrinprog = 0
        bucket = int(delta / reqbucketsize)
        if (minreqbucket > bucket) minreqbucket = bucket
        if (maxreqbucket < bucket) maxreqbucket = bucket
        if (rdwrKey[newtid] == "WRITE:")
          wrbuckets[bucket]++
        else if (rdwrKey[newtid] == "READ:")
          rdbuckets[bucket]++
        else
          buckets[bucket]++
        if (rdwrLen[newtid] != "")
        {
          if (rdwrKey[newtid] == "WRITE:")
            wrbucketBytes[bucket] += rdwrLen[newtid]
          else if (rdwrKey[newtid] == "READ:")
            rdbucketBytes[bucket] += rdwrLen[newtid]
          timebuck=int(newtime/timebucketsize);
          if (rdwrKey[newtid] == "WRITE:")
            wrbytessum[timebuck]+=rdwrLen[newtid];
          else
            rdbytessum[timebuck]+=rdwrLen[newtid];
          if (mintimebucket > timebuck) mintimebucket=timebuck;
          if (highbuck < timebuck) highbuck=timebuck
          delete rdwrLen[newtid]
          delete rdwrKey[newtid]
        }
      }
    }
    else if (index(recrest, "fastopen") > 0) {           # ????
      # Parse Var recrest "oiP" rest
      rest = stuffafter(recrest, "oiP")
      if (details)
        printf("%8d%s %17.9f Open  %s\n", newtid, cpusuff, newtime, rest)
    }
  }

  else if (index(recrest, "mmap process") > 0)
  {
    #old: mmap processBuf: bufP 0x54260E58 ...
    #     mmap processBuf exit: code 0 err 0
    #new: mmap processRead/Write enter: gnP 0x53677700
    #     mmap processRead/Write exit: code 0 err 0
    treq="mapbuf"
    ok=0
    if (index(recrest, "processRead") > 0)
    {
      treq="pagein"
      uioop[newtid] = 1
      ok=1
      rest = stuffafter(recrest, "processRead ")
      entexit = firstword(rest)
      rest = stuffafter(rest, entexit)
      if (entexit == "enter:") sawNewProcessRW = 1
    }
    else if (index(recrest, "processWrite") > 0)
    {
      treq="pageout"
      uioop[newtid] = 0
      ok=1
      rest = stuffafter(recrest, "processWrite ")
      entexit = firstword(rest)
      rest = stuffafter(rest, entexit)
      if (entexit == "enter:") sawNewProcessRW = 1
    }
    else if (index(recrest, "processBuf") > 0)
    {
      ok=1
      rest = stuffafter(recrest, "processBuf")
      if (substr(rest,1,6) == ": bufP")
      {
        entexit="enter:"
        rest = stuffafter(rest, ": ")
      }
      else
      {
        entexit = firstword(rest)
        rest = stuffafter(rest, entexit)
      }
      if (entexit == "enter:")
      {
        isrd = firstword(stuffafter(rest, "flags 0x"))
        isrd = substr(isrd,length(isrd),1)
        if (isrd == "1" || isrd == "3" || isrd == "5" || isrd == "7" ||
            isrd == "9" || isrd == "B" || isrd == "D" || isrd == "F")
          uioop[newtid] = 1
        else
          uioop[newtid] = 0
      }
      if (uioop[newtid] == 1)
        treq="pagein"
      else
        treq="pageout"
    }
    else if (index(recrest, "processClump:") > 0 && !sawNewProcessRW)
    {
      rest = stuffafter(recrest, "processClump:")
      entexit = "enter:"
      ok=1
      if (index(rest, "isRead 1") > 0)
      {
        treq="pagein"
        uioop[newtid] = 1
      }
      else
      {
        treq="pageout"
        uioop[newtid] = 0
      }
    }
    if (ok)
    {
      for (i = 1; i <= tidcount; i++)
        if (tids[i] == newtid) break
      if (i > tidcount)
      {
        tids[i] = newtid
        tidcount = i
      }
      if (entexit == "enter:")
      {
        for (wp = reqs[newtid]; wp >= 1; wp--)
          if (treq == req[newtid,wp])
            break;
        if (wp > 0)
        {
          # missed the exit from previous call, pretend like we are seeing one now
          exrc = ""  # unknown return code
          oldtimex = time[newtid,wp]
          oldlevel = level[newtid,wp]
          for (; wp < reqs[newtid]; wp++)
          {
            req[newtid,wp] = req[newtid,wp+1]
            time[newtid,wp] = time[newtid,wp+1]
            level[newtid,wp] = level[newtid,wp+1]
          }
          reqs[newtid]--
          delta = (newtime-oldtimex)*1000000
          if (delta >= 1000) mark = " +"
          else mark = ""
          if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
          else str=treq
          if (details)
            printf("%8d%s %17.9f %-20s %12.3f us%s%s\n", newtid, cpusuff, newtime, str, delta, mark, exrc)
          if (tlevel <= 0)
          {
            idleVFS = 0
            firstVFStime = 0.000000001
          }
          if (tlevel >= oldlevel && oldlevel >= 1)
          {
            tlevel = oldlevel - 1
            if (tlevel <= 0)
              idleVFSstart = newtime
          }
          lastVFStime = newtime
          if (reqs[newtid] == 0) {
            timein[newtid] += newtime-oldtimex
            idlestart[newtid] = newtime
            tidopcnt[newtid]++
          }
          timeop[treq] += newtime-oldtimex
          cntop[treq]++
          if (IOhist)
          {
            delta = delta/1000000
            totaldelta += delta
            totalrdwrs++
            if (rdwrinprog > maxrdwrinprog) maxrdwrinprog=rdwrinprog
            rdwrinprog--
            if (rdwrinprog < 0) rdwrinprog = 0
            bucket = int(delta / reqbucketsize)
            if (minreqbucket > bucket) minreqbucket = bucket
            if (maxreqbucket < bucket) maxreqbucket = bucket
            if (rdwrKey[newtid] == "WRITE:")
              wrbuckets[bucket]++
            else if (rdwrKey[newtid] == "READ:")
              rdbuckets[bucket]++
            else
              buckets[bucket]++
            if (rdwrLen[newtid] != "")
            {
              if (rdwrKey[newtid] == "WRITE:")
                wrbucketBytes[bucket] += rdwrLen[newtid]
              else if (rdwrKey[newtid] == "READ:")
                rdbucketBytes[bucket] += rdwrLen[newtid]
              timebuck=int(newtime/timebucketsize);
              if (rdwrKey[newtid] == "WRITE:")
                wrbytessum[timebuck]+=rdwrLen[newtid];
              else
                rdbytessum[timebuck]+=rdwrLen[newtid];
              if (mintimebucket > timebuck) mintimebucket=timebuck;
              if (highbuck < timebuck) highbuck=timebuck
              delete rdwrLen[newtid]
              delete rdwrKey[newtid]
            }
          }
        }
        pbgnp[newtid] = firstword(stuffafter(rest, "gnP "))
        if (IOhist)
        {
          rdwrinprog++
          inpbucket[rdwrinprog]++
        }
        if (tlevel == 0)
        {
          if (firstVFStime == 0) firstVFStime = newtime
          if (idleVFSstart != 0)
          {
            idleVFS += newtime - idleVFSstart
            idleVFSstart = 0
          }
        }
        tlevel = tlevel + 1
        reqi = reqs[newtid]+1
        reqs[newtid] = reqi
        req[newtid,reqi] = treq
        time[newtid,reqi] = newtime
        level[newtid,reqi] = tlevel
        if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
        else str=treq
        if (idlestart[newtid] != "") {
          idletime = newtime-idlestart[newtid]
          if (details)
            printf("%8d%s %17.9f %-33s ext %12.3f us\n", newtid, cpusuff, newtime, str, idletime*1000000)
        }
        else if (details)
          printf("%8d%s %17.9f %s\n", newtid, cpusuff, newtime, str)
        if (idlestart[newtid] != "") {
          timeout[newtid] += idletime
          idlestart[newtid] = ""
        }
      }

      else if (entexit == "exit:") {
        exrc = firstword(stuffafter(rest, " rc "))
        if (exrc == "") exrc = firstword(stuffafter(rest, " err "))
        if (exrc == "0") exrc = ""
        else if (exrc == "2" && treq == "lookup") exrc = " NOTFOUND"
        else if (exrc == "25" && treq == "ioctl") exrc = " NOTTY"
        else if (exrc != "") exrc = " err="exrc
        for (wp = reqs[newtid]; wp >= 1; wp--)
          if (treq == req[newtid,wp])
            break;
        if (wp > 0) {
          oldtimex = time[newtid,wp]
          oldlevel = level[newtid,wp]
          for (; wp < reqs[newtid]; wp++)
          {
            req[newtid,wp] = req[newtid,wp+1]
            time[newtid,wp] = time[newtid,wp+1]
            level[newtid,wp] = level[newtid,wp+1]
          }
          reqs[newtid]--
          delta = (newtime-oldtimex)*1000000
          if (delta >= 1000) mark = " +"
          else mark = ""
          if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
          else str=treq
          if (details)
            printf("%8d%s %17.9f %-20s %12.3f us%s%s\n", newtid, cpusuff, newtime, str, delta, mark, exrc)
          if (tlevel <= 0)
          {
            idleVFS = 0
            firstVFStime = 0.000000001
          }
          if (tlevel >= oldlevel && oldlevel >= 1)
          {
            tlevel = oldlevel - 1
            if (tlevel <= 0)
              idleVFSstart = newtime
          }
          lastVFStime = newtime
          if (reqs[newtid] == 0) {
            timein[newtid] += newtime-oldtimex
            idlestart[newtid] = newtime
            tidopcnt[newtid]++
          }
          timeop[treq] += newtime-oldtimex
          cntop[treq]++
          if (IOhist)
          {
            delta = delta/1000000
            totaldelta += delta
            totalrdwrs++
            if (rdwrinprog > maxrdwrinprog) maxrdwrinprog=rdwrinprog
            rdwrinprog--
            if (rdwrinprog < 0) rdwrinprog = 0
            bucket = int(delta / reqbucketsize)
            if (minreqbucket > bucket) minreqbucket = bucket
            if (maxreqbucket < bucket) maxreqbucket = bucket
            if (rdwrKey[newtid] == "WRITE:")
              wrbuckets[bucket]++
            else if (rdwrKey[newtid] == "READ:")
              rdbuckets[bucket]++
            else
              buckets[bucket]++
            if (rdwrLen[newtid] != "")
            {
              if (rdwrKey[newtid] == "WRITE:")
                wrbucketBytes[bucket] += rdwrLen[newtid]
              else if (rdwrKey[newtid] == "READ:")
                rdbucketBytes[bucket] += rdwrLen[newtid]
              timebuck=int(newtime/timebucketsize);
              if (rdwrKey[newtid] == "WRITE:")
                wrbytessum[timebuck]+=rdwrLen[newtid];
              else
                rdbytessum[timebuck]+=rdwrLen[newtid];
              if (mintimebucket > timebuck) mintimebucket=timebuck;
              if (highbuck < timebuck) highbuck=timebuck
              delete rdwrLen[newtid]
              delete rdwrKey[newtid]
            }
          }
        }
        else {
          if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
          else str=treq
          if (details)
            printf("%8d%s %17.9f %-20s **************%s\n", newtid, cpusuff, newtime, str, exrc)
          if (tlevel <= 0)
          {
            idleVFS = 0
            firstVFStime = 0.000000001
          }
          else
          {
            tlevel = tlevel - 1
            if (tlevel <= 0)
              idleVFSstart = newtime
          }
          lastVFStime = newtime
        }
      }
      else if (!havemmapwrite && substr(rest,1,5) == " lock")
      {
        #  lock block 0:233 offset 0 pos 0x0000000000E90000
        $0 = rest
        if (IOhist)
        {
          rdwrKey[newtid] = "WRITE:"
          rdwrLen[newtid] = 4096
        }
        gnP = pbgnp[newtid]
        if (inodeOFgnode[gnP] != "") inode = inodeOFgnode[gnP]
        else inode = -1
        if ($3 == "0:0")
        {
          if (sectorsPerBlockA[inode] != "")
            blocklen = sectorsPerBlockA[inode]
          else
            blocklen = -1
        }
        else
        {
          blocklen = (x2d(substr($NF,3)) - $5) / substr($3,3)
          sectorsPerBlockA[inode] = blocklen / 512
        }
        if (details)
          printf("%8d%s %17.9f WRITE: gnP %s inode %s snap 0 oiP 0xFFFFFFFF offset %s len 4096 blkSize %s opt 00000008\n", newtid, cpusuff, newtime, gnP, inode, $NF, blocklen)
      }
    }
  }
  else if (index(recrest, "DMAPI: mmfs_") > 0)
  {
    rest=stuffafter(recrest, "DMAPI: mmfs_")
    treq=firstword(rest)
    rest=stuffafter(rest, treq)
    entexit=firstword(rest)
    rest=stuffafter(rest, entexit)
    for (i = 1; i <= tidcount; i++)
      if (tids[i] == newtid) break
    if (i > tidcount)
    {
      tids[i] = newtid
      tidcount = i
    }
    if (entexit == "enter:") {
      if (substr(treq,1,4) == "rdwr") {
        op = firstword(stuffafter(rest, " op "))
        if (op == "0") uioop[newtid] = "1"
        else if (op == "1") uioop[newtid] = "0"
        if (IOhist)
        {
          rdwrinprog++
          inpbucket[rdwrinprog]++
        }
      }
      if (tlevel == 0)
      {
        if (firstVFStime == 0) firstVFStime = newtime
        if (idleVFSstart != 0)
        {
          idleVFS += newtime - idleVFSstart
          idleVFSstart = 0
        }
      }
      tlevel = tlevel + 1
      reqi = reqs[newtid]+1
      reqs[newtid] = reqi
      req[newtid,reqi] = treq
      time[newtid,reqi] = newtime
      level[newtid,reqi] = tlevel
      if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
      else str=treq
      if (idlestart[newtid] != "") {
        idletime = newtime-idlestart[newtid]
        if (details)
          printf("%8d%s %17.9f %-33s ext %12.3f us\n", newtid, cpusuff, newtime, str, idletime*1000000)
      }
      else if (details)
        printf("%8d%s %17.9f %s\n", newtid, cpusuff, newtime, str)
      if (idlestart[newtid] != "") {
        timeout[newtid] += idletime
        idlestart[newtid] = ""
      }
    }

    else if (entexit == "exit:") {
      exrc = firstword(stuffafter(rest, " rc "))
      if (exrc == "0") exrc = ""
      else if (exrc == "2" && treq == "lookup") exrc = " NOTFOUND"
      else if (exrc == "25" && treq == "ioctl") exrc = " NOTTY"
      else if (exrc != "") exrc = " err="exrc
      for (wp = reqs[newtid]; wp >= 1; wp--)
        if (treq == req[newtid,wp])
          break;
      if (wp > 0) {
        oldtimex = time[newtid,wp]
        oldlevel = level[newtid,wp]
        for (; wp < reqs[newtid]; wp++)
        {
          req[newtid,wp] = req[newtid,wp+1]
          time[newtid,wp] = time[newtid,wp+1]
          level[newtid,wp] = level[newtid,wp+1]
        }
        reqs[newtid]--
        delta = (newtime-oldtimex)*1000000
        if (delta >= 1000) mark = " +"
        else mark = ""
        if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
        else str=treq
        if (details)
          printf("%8d%s %17.9f %-20s %12.3f us%s%s\n", newtid, cpusuff, newtime, str, delta, mark, exrc)
        if (tlevel <= 0)
        {
          idleVFS = 0
          firstVFStime = 0.000000001
        }
        if (tlevel >= oldlevel && oldlevel >= 1)
        {
          tlevel = oldlevel - 1
          if (tlevel <= 0)
            idleVFSstart = newtime
        }
        lastVFStime = newtime
        if (reqs[newtid] == 0) {
          timein[newtid] += newtime-oldtimex
          idlestart[newtid] = newtime
          tidopcnt[newtid]++
        }
        timeop[treq] += newtime-oldtimex
        cntop[treq]++
      }
      else
      {
        if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
        else str=treq
        if (details)
          printf("%8d%s %17.9f %-20s*************%s\n", newtid, cpusuff, newtime, str, exrc)
        if (tlevel <= 0)
        {
          idleVFS = 0
          firstVFStime = 0.000000001
        }
        else
        {
          tlevel = tlevel - 1
          if (tlevel <= 0)
            idleVFSstart = newtime
        }
        lastVFStime = newtime
      }
      if (IOhist && wp > 0 && substr(treq,1,4) == "rdwr")
      {
        delta = delta/1000000
        totaldelta += delta
        totalrdwrs++
        if (rdwrinprog > maxrdwrinprog) maxrdwrinprog=rdwrinprog
        rdwrinprog--
        if (rdwrinprog < 0) rdwrinprog = 0
        bucket = int(delta / reqbucketsize)
        if (minreqbucket > bucket) minreqbucket = bucket
        if (maxreqbucket < bucket) maxreqbucket = bucket
        if (rdwrKey[newtid] == "WRITE:")
          wrbuckets[bucket]++
        else if (rdwrKey[newtid] == "READ:")
          rdbuckets[bucket]++
        else
          buckets[bucket]++
        if (rdwrLen[newtid] != "")
        {
          if (rdwrKey[newtid] == "WRITE:")
            wrbucketBytes[bucket] += rdwrLen[newtid]
          else if (rdwrKey[newtid] == "READ:")
            rdbucketBytes[bucket] += rdwrLen[newtid]
          timebuck=int(newtime/timebucketsize);
          if (rdwrKey[newtid] == "WRITE:")
            wrbytessum[timebuck]+=rdwrLen[newtid];
          else
            rdbytessum[timebuck]+=rdwrLen[newtid];
          if (mintimebucket > timebuck) mintimebucket=timebuck;
          if (highbuck < timebuck) highbuck=timebuck
          delete rdwrLen[newtid]
          delete rdwrKey[newtid]
        }
      }
    }
  }

  else if (index(recrest, "ESTALE") > 0)
  {
    rest = stuffafter(recrest, "VNODE:")
    for (i = 1; i <= tidcount; i++)
      if (tids[i] == newtid) break
    if (i > tidcount)
    {
      tids[i] = newtid
      tidcount = i
    }
    exrc = " err=ESTALE"
    wp = reqs[newtid]
    if (wp > 0) {
      treq = req[newtid,wp]
      oldtimex = time[newtid,wp]
      oldlevel = level[newtid,wp]
      for (; wp < reqs[newtid]; wp++)
      {
        req[newtid,wp] = req[newtid,wp+1]
        time[newtid,wp] = time[newtid,wp+1]
        level[newtid,wp] = level[newtid,wp+1]
      }
      reqs[newtid]--
      delta = (newtime-oldtimex)*1000000
      if (delta >= 1000) mark = " +"
      else mark = ""
      if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
      else str=treq
      if (details)
        printf("%8d%s %17.9f %-20s %12.3f us%s%s\n", newtid, cpusuff, newtime, str, delta, mark, exrc)
      if (tlevel <= 0)
      {
        idleVFS = 0
        firstVFStime = 0.000000001
      }
      if (tlevel >= oldlevel && oldlevel >= 1)
      {
        tlevel = oldlevel - 1
        if (tlevel <= 0)
          idleVFSstart = newtime
      }
      lastVFStime = newtime
    }
  }

  else if (index(recrest, "kSFSAcquireFcntlBRT exit:") > 0) {
  }

  else if (index(recrest, "VNOP:") > 0) {
    rest = stuffafter(recrest, "VNOP: ")
    $0 = rest
    gni =index($0, "gnP ")
    ini =index($0, "inode ")
    if (gni > 0 && ini > 0)
    {
      gnP = firstword(substr($0,gni+4))
      inode = firstword(substr($0,ini+6))
      inodeOFgnode[gnP] = inode
      gnodeOFinode[inode] = gnP
    }
    if ($1 == "READ:" || $1 == "WRITE:")
    {
      if (IOhist && (key == "READ:" || $NF != "0000000C"))
      {
        rdwrKey[newtid] = $1
        if ($2 == "inode")
          rdwrLen[newtid] = $9
        else if ($6 != "snap")
          rdwrLen[newtid] = $11
        else
          rdwrLen[newtid] = $13
      }
      if ($NF == "00000008") havemmapwrite=1
    }
    else if ($1 == "GETVATTR:")
    {
      if ($5 == "3") nameofvp[$3] = "."
      else if (nameofvp[$3] != "")  rest = rest " " nameofvp[$3]
    }
    else if ($1 == "LOCKCTL:")
    {
      if (index(rest, "lckdat") > 0)
      {
        lcmd = firstword(stuffafter(rest, "cmd 0x0000000"))
        ltyp = firstword(stuffafter(rest, "type "))
        if (lcmd == 2) lcmd = "SET"
        else if (lcmd == 6) lcmd = "SET+WAIT"
        else if (lcmd == 0) lcmd = "QUERY"
        else if (lcmd == 1) lcmd = "QUERY+INOFLCK"
        else if (lcmd == 3) lcmd = "SET+INOFLCK"
        else if (lcmd == 4) lcmd = "QUERY+WAIT"
        else if (lcmd == 5) lcmd = "QUERY+INOFLCK+WAIT"
        else if (lcmd == 7) lcmd = "SET+INOFLCK+WAIT"
        if (ltyp == 1) ltyp = "RDLCK"
        else if (ltyp == 2) ltyp = "WRLCK"
        else if (ltyp == 3) {ltyp = "UNLCK"; if (lcmd == "SET") lcmd=""}
        rest = substr(rest, 1, index(rest, "lckdat")-1) lcmd " " ltyp
      }
      if (nameofvp[$2] != "")  rest = rest " " nameofvp[$2]
    }
    else if ($1 == "LOOKUP:")
    {
      # LOOKUP: vP 0x34CF58C4 inode 838030 snap 0 dvP 0x35146DA4 name 'wrfrst_01_000288'
      # LOOKUP: vP 0x32E31418 gnP 0x331FDF00 inode 39937 snap 0 dvP 0x32E43F44 name 'testfile'
      # LOOKUP: not found dvP 0x3512AE0C gnDirP 0x3512AE0C name 'external'
      name = substr($0, index($0, "'")+1)
      name = substr(name,1,length(name)-1)
      dvp = firstword(stuffafter(rest, "dvP"))
      gnp = firstword(stuffafter(rest, "gnDirP"))
      if (gnp != "")
        dvpofgnp[gnp] = dvp

      if ($2 == "vP")
      {
        inode=firstword(stuffafter(rest, "inode "))
        if (nameofvp[dvp] != "")
        {
          if (name == ".")
          {
            if (nameofvp[dvp] == ".") name = dvp
            else name = nameofvp[dvp]
          }
          else if (name == "..")
          {
            #?? check inode of xxx/yyy/.. == inode of xxx
            pos = lastpos(nameofvp[dvp], "/")
            if (pos > 0) name = substr(nameofvp[dvp],1,pos-1)
            else name = $3
          }
          else
            name = nameofvp[dvp]"/"name
        }
        if (name == ".") nameofvp[$3] = $3
        else nameofvp[$3] = name
      }
      else
      {
        inode="notfound"
        if (nameofvp[dvp] != "") name = nameofvp[dvp]"/"name
      }
      lookups[inode,name] ++
      if (nameofvp[dvp] != "") rest = rest " in " nameofvp[dvp]
    }
    else if ($1 == "CREATE:")
    {
      # CREATE: gnDirP 0x1010C2A97F8 dinode 23950289 flags 0xC2 mode 0x81A4 inode 2086233 oiP 0x0 name '.testfile.shfp.121423'

      name = substr($0, index($0, "'")+1)
      name = substr(name,1,length(name)-1)
      gnp = firstword(stuffafter(rest, "gnDirP"))
      inode=firstword(stuffafter(rest, " inode "))
      dvp = dvpofgnp[gnp]
      if (dvp != "" && nameofvp[dvp] != "")
      {
        name = nameofvp[dvp]"/"name
        rest = rest " in " nameofvp[dvp]
      }
      lookups[inode,name] ++
    }
    else if ($2 == "vP" && nameofvp[$3] != "")  rest = rest " " nameofvp[$3]
    else if ($2 == "dvP" && nameofvp[$3] != "")  rest = rest " in " nameofvp[$3]
    if (details)
      printf("%8d%s %17.9f %s\n", newtid, cpusuff, newtime, rest)
  }

  else if (index(recrest, "KSVFS: ruWait") > 0)
    ruwaitStart[newtid] = newtime
  else if (index(recrest, "KSVFS: DeclareResourceUsage") > 0)
  {
    if (ruwaitStart[newtid] > 0 &&
        (index(recrest, " err ") > 0 || index(recrest, " rc ") > 0))
    {
      ruwait = newtime - ruwaitStart[newtid]
      ruwaitStart[newtid] = 0
      treq = req[newtid,1]
      tlevel = level[newtid,1]
      if (oldcmd[newcpu] != "") str=treq "(" oldcmd[newcpu] ")"
      else str=treq
      ruwaitop[treq] += ruwait
      if (details)
        printf("%8d%s %17.9f %-33s ruWait %12.3f us\n", newtid, cpusuff, newtime, str, ruwait*1000000)
    }
  }

  else if (details && index(recrest, "kSFSOpen enter") > 0) {
    rest = stuffafter(recrest, "genNum")
    printf("%8d%s %17.9f Open gen %s\n", newtid, cpusuff, newtime, rest)
  }

  if (traceIO)
  {
    if (index(recrest, "IO:") > 0) {
      rest = stuffafter(recrest, "IO: ")
      if (index(rest, "QIO:") > 0)
      {
        if (index(rest, "DIOQIO:") > 0) 
          DIOQIO = 1
        else 
        {
          DIOQIO = 0
          buffer = firstword(stuffafter(rest,"buf "))
          if (substr(buffer,1,2) == "0x") buffer = substr(buffer,3)
        }
        da = firstword(stuffafter(rest," da "))
        buffer = buffer" "da
        if (index(rest, "nsdId") > 0)
          disk = firstword(stuffafter(rest,"nsdId "))
        else if (index(rest, "nsdName") > 0)
        {
          disk = firstword(stuffafter(rest,"nsdName "))
          nsdname[da] = disk
        }
        else
        {
          disk = firstword(stuffafter(rest,"disk "))
          # old traces for nsd disks, can be 2 writes using same buffer
          if ((disk == "FFFFFFFF" || disk == "00000000FFFFFFFF") && QIOtime[buffer,disk] != "")
            disk = "FFFFFFFE"
        }
        # Since DIOQIO trace no longer prints out buffer, only 
        # do this for regular IO
        if ( !DIOQIO ) 
        {
          QIOtime[buffer,disk] = newtime
          QIOtid[buffer,disk] = newtid
          QIOdepth[buffer,disk] = qiosdisk[disk]
        }
        qios++
        ioinpbucket[qios]++
        qiosdisk[disk]++
        if (idlediskFirst[disk] == 0) idlediskFirst[disk] = newtime
        if (idlediskStart[disk] != 0 && qiosdisk[disk] == 1)
        {
          idlediskTime[disk] += newtime-idlediskStart[disk]
          idlediskStart[disk] = 0
        }
        threadname=stuffafter(rest,"(")
        threadname=substr(threadname,1,length(threadname)-1)
        rdwrtype=firstword(stuffafter(rest,"QIO: "))
        rdwrdata=firstword(stuffafter(rest,rdwrtype" "))
        t = sprintf("%-5s %-12s %s",rdwrtype, rdwrdata, threadname)
        QIOtype[t]++

        if (details)
          printf("%8d%s %17.9f %s qlen %d\n", newtid, cpusuff, newtime, rest, qiosdisk[disk])
      }
      else if (index(rest, "SIO:") > 0 && DIOQIO)
      {   
        buffer = firstword(stuffafter(rest,"buf "))
        if (substr(buffer,1,2) == "0x") buffer = substr(buffer,3)
        da = firstword(stuffafter(rest," da "))
        buffer = buffer" "da
        if (index(rest, "nsdId") > 0)
          disk = firstword(stuffafter(rest,"nsdId "))
        else if (index(rest, "nsdName") > 0)
        {
          disk = firstword(stuffafter(rest,"nsdName "))
          nsdname[da] = disk
        }
        else if (index(rest, "file") > 0)
          disk = firstword(stuffafter(rest,"file "))
        else
          disk = firstword(stuffafter(rest,"disk "))
        QIOtime[buffer,disk] = newtime
        QIOtid[buffer,disk] = newtid
        qios++
        ioinpbucket[qios]++
        QIOdepth[buffer,disk] = qiosdisk[disk]
        qiosdisk[disk]++
        if (idlediskFirst[disk] == 0)
        {
          idlediskFirst[disk] = newtime
          idlediskLast[disk] = newtime
        }
        if (idlediskStart[disk] != 0 && qiosdisk[disk] == 1)
        {
          idlediskTime[disk] += newtime-idlediskStart[disk]
          idlediskStart[disk] = 0
        }

        if (details)
          printf("%8d%s %17.9f %s qlen %d\n", newtid, cpusuff, newtime, rest, qiosdisk[disk])
      }
      else if (index(rest, "FIO:") > 0)
      {
        buffer = firstword(stuffafter(rest,"buf "))
        if (substr(buffer,1,2) == "0x") buffer = substr(buffer,3)
        da = firstword(stuffafter(rest," da "))
        buffer = buffer" "da
        if (index(rest, "nsdId") > 0 || index(rest, "nsdName") > 0)
        {
          if (index(rest, "nsdId") > 0)
          {
            disk = firstword(stuffafter(rest,"nsdId "))
            if (nsdname[da] != "") disk = nsdname[da]
          }
          else if (index(rest, "nsdName") > 0)
            disk = firstword(stuffafter(rest,"nsdName "))
          delete nsdname[da]
          if (QIOtime[buffer,disk] == "")
            if (QIOtime[buffer,"FFFFFFFF"] != "")
              tdsk = "FFFFFFFF"
            else if (QIOtime[buffer,"00000000FFFFFFFF"] != "")
              tdsk = "00000000FFFFFFFF"
            else if (QIOtime[buffer,"FFFFFFFE"] != "")
              tdsk = "FFFFFFFE"
            else tdsk=""
            if (tdsk != "")
            {
              QIOtime[buffer,disk] = QIOtime[buffer,tdsk]
              delete QIOtime[buffer,tdsk]
            }
        }
        else
          disk = firstword(stuffafter(rest,"disk "))
        if (QIOtime[buffer,disk] != "")
          delta = (newtime-QIOtime[buffer,disk])*1000000
        else delta = 0
        effqueued = 0
        if (QIOtime[buffer,disk] > 0)
        {
          nios[disk]++
          if (maxqios < qios) maxqios = qios
          if (qios > 0) qios--
          if (maxqiosdisk[disk] < qiosdisk[disk]) maxqiosdisk[disk] = qiosdisk[disk]
          if (qiosdisk[disk] > 0) qiosdisk[disk]--
          if (qiosdisk[disk] > 0)
            lastfio[disk] = newtime
          else
          {
            if (lastfio[disk] > 0)
            {
              effQIOtime[buffer,disk] = lastfio[disk]
              lastfio[disk] = 0
              if (QIOtime[buffer,disk] == 0)
                QIOtime[buffer,disk] = effQIOtime[buffer,disk]
              effqueued = (effQIOtime[buffer,disk]-QIOtime[buffer,disk])*1000000
            }
            idlediskStart[disk] = newtime
            idlediskLast[disk] = newtime
          }
        }
        if (details)
          printf("%8d%s %17.9f %s qlen %d duration %.3f us queued %.3f us\n", QIOtid[buffer,disk], cpusuff, newtime, rest, qiosdisk[disk], delta, effqueued)
        if (IOhist)
        {
          $0 = rest
          nSectors = firstword(stuffafter(rest,"nSectors "))
          if (QIOtime[buffer,disk] > 0)
          {
            delta = newtime-QIOtime[buffer,disk]
            totaliodelta += delta
            totalios++
            bucket = int(delta / iobucketsize)
            if (miniobucket > bucket) miniobucket = bucket
            if (maxiobucket < bucket) maxiobucket = bucket

            timebuck=int(newtime/timebucketsize);
            if (mintimebucket > timebuck) mintimebucket=timebuck;
            if (highbuck < timebuck) highbuck=timebuck
            if (nSectors > maxSectors) maxSectors = nSectors
            iobucketqios[bucket]+=QIOdepth[buffer,disk]
            iobucketDqios[disk,bucket]+=QIOdepth[buffer,disk]
            if ($2 == "read")
            {
              rdsectsum[timebuck]+=nSectors;
              rdiobuckets[bucket]++
              rdiobucketBytes[bucket] += nSectors*512
              rdsectbucket[nSectors]++
              rdiobucketsD[disk,bucket]++
              rdiobucketDBytes[disk,bucket] += nSectors*512
            }
            else
            {
              wrsectsum[timebuck]+=nSectors;
              wriobuckets[bucket]++
              wriobucketBytes[bucket] += nSectors*512
              wrsectbucket[nSectors]++
              wriobucketsD[disk,bucket]++
              wriobucketDBytes[disk,bucket] += nSectors*512
            }
            disklist[disk]=1
            totaliodeltaD[disk] += delta
            totaliosD[disk]++

            if (effqueued > 0 && newtime > QIOtime[buffer,disk])
              effdelta = newtime-effQIOtime[buffer,disk]
            else
              effdelta = delta
            efftotaliodelta += effdelta
            effbucket = int(effdelta / iobucketsize)
            if (miniobucket > effbucket) miniobucket = effbucket
            if (maxiobucket < effbucket) maxiobucket = effbucket
            if ($2 == "read")
            {
              effrdiobuckets[effbucket]++
              effrdiobucketBytes[effbucket] += nSectors*512
              effrdiobucketsD[disk,effbucket]++
              effrdiobucketDBytes[disk,effbucket] += nSectors*512
            }
            else
            {
              effwriobuckets[effbucket]++
              effwriobucketBytes[effbucket] += nSectors*512
              effwriobucketsD[disk,effbucket]++
              effwriobucketDBytes[disk,effbucket] += nSectors*512
            }
            efftotaliodeltaD[disk] += effdelta
            delete QIOdepth[buffer,disk]
          }
        }
        delete QIOtime[buffer,disk]
        delete effQIOtime[buffer,disk]
      }
    }

    else if (index(recrest, "SFSRelAll") > 0) {
      rest = stuffafter(recrest, "SFSRelAll")
      if (details)
        printf("%8d%s %17.9f release all%s\n", newtid, cpusuff, newtime, rest)
    }

    else if (index(recrest, "relAll") > 0) {
      rest = stuffafter(recrest, "discarding")
      if (details)
        printf("%8d%s %17.9f release all discarding:%s\n", newtid, cpusuff, newtime, rest)
    }

    else if (index(recrest, "startSeqStream") > 0) {
      rest = stuffafter(recrest, "startSeqStream")
      if (details)
        printf("%8d%s %17.9f startSeqStream%s\n", newtid, cpusuff, newtime, rest)
    }

    else if (index(recrest, "Buffer release") > 0) {
      rest = stuffafter(recrest, ": ")
      if (details)
        printf("%8d%s %17.9f %s\n", newtid, cpusuff, newtime, rest)
    }

    else if (index(recrest, "uiomove") > 0) {
      rest = stuffafter(recrest, "kSFSRdWr")
      # if (details)
        # printf("%8d%s %17.9f kSFSRdWr%s\n", newtid, cpusuff, newtime, rest)
    }
  }

  if (traceBR)
  {
    # TSTM: HandleTellRequest: downgrade BR key 09010DCE:3C0FB53B:00000003:00000000 0x0000000000018000-0x0000000000019FFF to nl node 1
    # TSTM: HandleBRTellRequest: downgrade BR key 09010DCE:3D41D263:0000005B:00000000 range 0x0000000000380000-0x00000000003BFFFF to nl node 1 seqNum 0:140 client seqNum 0:140
    # TSTM: HandleBRTellRequest: granting tokType BR range 0x0000000000018000-0x0000000000019FFF mode xw key 09010DCE:3C0FB53B:00000003:00000000 to node 1
    # TSTM: HandleBRTellRequest: granting tokType BR key 09010DCE:3D41D263:0000005B:00000000 range 0x0000000000380000-0x00000000003BFFFF mode xw to node 2 seqNum 0:144
    if (index(recrest, "downgrade BR key") > 0)
    {
      key = firstword(stuffafter(recrest, "key "))
      rest = stuffafter(recrest, key)
      range = firstword(rest)
      if (range == "range") range = firstword(stuffafter(rest,"range "))
      mode = firstword(stuffafter(rest,"to "))
      node = firstword(stuffafter(rest,"node "))
      if (details)
        printf("%8d%s %17.9f BR: downgrade mode %s node %s key %s range %s\n", newtid, cpusuff, newtime, mode, node, key, range)
    }
    else if (index(recrest, "granting tokType BR") > 0)
    {
      rest = stuffafter(recrest, "BR ")
      range = firstword(stuffafter(rest,"range "))
      key = firstword(stuffafter(rest,"key "))
      mode = firstword(stuffafter(rest,"mode "))
      node = firstword(stuffafter(rest,"node "))
      if (details)
        printf("%8d%s %17.9f BR: granting  mode %s node %s key %s range %s\n", newtid, cpusuff, newtime, mode, node, key, range)
    }
  }

  if (traceTok)
  {
    if (index(recrest, ": -BR") > 0|| index(recrest, ": +BR") > 0) {
      # Parse Var recrest "TSTM: " rest
      rest = stuffafter(recrest, "TSTM: ")
      if (details)
        printf("%8d%s %17.9f TM: %s\n", newtid, cpusuff, newtime, rest)
    }
    else if (index(recrest, "TellServer upgrade token") > 0) {
      upgrademode = firstword(stuffafter(recrest, "mode"))
    }

    else if (index(recrest, "              Range:") > 0) {
      # Parse Var recrest "Range:0x"s1" - 0x"e1", DesRange:0x"ds1" - 0x"de1
      s1 = firstword(stuffafter(recrest, " Range:0x"))
      e1 = firstword(stuffafter(recrest, " - 0x"))
      if (substr(e1,length(e1)) == ",") e1 = substr(e1,1,length(e1)-1)
      ds1 = firstword(stuffafter(recrest, ", DesRange:0x"))
      de1 = firstword(stuffafter(recrest, ds1 " - 0x"))
      if (details)
        printf("%8d%s %17.9f change token mode %s range %s-%s desrange %s-%s\n", newtid, cpusuff, newtime, upgrademode, s1, e1, ds1, de1)
    }

    else if (index(recrest, "relinquishBRT") > 0) {
      # Parse Var recrest "relinquishBRT "entex" range "s1":"s2"-"e1":"e2 rest
      entex = firstword(stuffafter(recrest, "relinquishBRT"))
      inode = firstword(stuffafter(recrest, "inode "))
      ranges = firstword(stuffafter(recrest, "range "))
      rest = stuffafter(recrest, ranges)
      pos = index(ranges,":")
      if (pos > 0)
      {
        pos = index(ranges,"-")
        range1 = substr(ranges,1,pos-1)
        range2 = substr(ranges,pos+1)
        pos = index(range1,":")
        if (pos > 0) s1 = substr(range1,1,pos-1) substr(range1, pos+1)
        else s1 = range1
        pos = index(range2,":")
        if (pos > 0) e1 = substr(range2,1,pos-1) substr(range2, pos+1)
        else e1 = range1
        ranges = d2x(s1,16) "-" d2x(e1,16)
      }
      if (details)
        printf("%8d%s %17.9f relinquishBRT %s inode %s range %s %s\n", newtid, cpusuff, newtime, entex, inode, ranges, rest)
    }

    else if (index(recrest, "GetSubIndirectBlock inode") > 0) {
      # Parse Var recrest "GetSubIndirectBlock" rest
      rest = stuffafter(recrest, "GetSubIndirectBlock")
      if (details)
        printf("%8d%s %17.9f GetSubIndirectBlock %s\n", newtid, cpusuff, newtime, rest)
    }

    else if (index(recrest, "token_revoke enter") > 0) {
      # Parse Var recrest "token_revoke enter" rest
      rest = stuffafter(recrest, "token_revoke enter")
      if (details)
        printf("%8d%s %17.9f token_revoke %s\n", newtid, cpusuff, newtime, rest)
    }

    else if (index(recrest, "acquireBRT") > 0) {
      if (index(recrest, "acquireBRT(): enter") > 0) {
        # Parse Var recrest "acquireBRT(): "entex" req" s1":"s2"-"e1":"e2 rest
        entex = firstword(stuffafter(recrest, "acquireBRT(): "))
        inode = firstword(stuffafter(recrest, "inode "))
        ranges = firstword(stuffafter(recrest, " req "))
        rest = stuffafter(recrest, ranges)
        pos = index(ranges,":")
        if (pos > 0)
        {
          pos = index(ranges,"-")
          range1 = substr(ranges,1,pos-1)
          range2 = substr(ranges,pos+1)
          pos = index(range1,":")
          if (pos > 0) s1 = substr(range1,1,pos-1) substr(range1, pos+1)
          else s1 = range1
          pos = index(range2,":")
          if (pos > 0) e1 = substr(range2,1,pos-1) substr(range2, pos+1)
          else e1 = range1
          ranges = d2x(s1,16) "-" d2x(e1,16)
        }
        if (details)
          printf("%8d%s %17.9f acquireBRT %s inode %s req %s %s\n", newtid, cpusuff, newtime, entex, inode, ranges, rest)
      }
      else if (index(recrest, "acquireBRT: inode") > 0) {
        # Parse Var recrest "acquireBRT: "entex" gra" s1":"s2"-"e1":"e2 rest
        entex = "inode"
        inode = firstword(stuffafter(recrest, "inode "))
        ranges = firstword(stuffafter(recrest, " gra "))
        rest = stuffafter(rest, ranges)
        pos = index(ranges,":")
        if (pos > 0)
        {
          pos = index(ranges,"-")
          range1 = substr(ranges,1,pos-1)
          range2 = substr(ranges,pos+1)
          pos = index(range1,":")
          if (pos > 0) s1 = substr(range1,1,pos-1) substr(range1, pos+1)
          else s1 = range1
          pos = index(range2,":")
          if (pos > 0) e1 = substr(range2,1,pos-1) substr(range2, pos+1)
          else e1 = range1
          ranges = d2x(s1,16) "-" d2x(e1,16)
        }
        if (details)
          printf("%8d%s %17.9f acquireBRT %s inode %s gra %s %s\n", newtid, cpusuff, newtime, entex, inode, ranges, rest)
      }
      else if (index(recrest, "acquireBRT(): exit") > 0) {
        rest = stuffafter(recrest, "acquireBRT():")
        if (details)
          printf("%8d%s %17.9f acquireBRT%s\n", newtid, cpusuff, newtime, rest)
      }
    }

    else if (index(recrest, "RevokeFromClients") > 0) {
      if (index(recrest, "newmode") > 0 ||
          index(recrest, "revoking from ") > 0 ||
          index(recrest, "returning") > 0)
      {
        rest = stuffafter(recrest, "RevokeFromClients")
        if (substr(rest,1,6) == "() -- ")
          rest = substr(rest,7)
        if (details)
          printf("%8d%s %17.9f RevokeFromClients %s\n", newtid, cpusuff, newtime, rest)
      }
    }

    else if (index(recrest, "check_dc: enter") > 0) {
      rest = stuffafter(recrest, "check_dc")
      if (details)
        printf("%8d%s %17.9f check_dc%s\n", newtid, cpusuff, newtime, rest)
    }

  }

  if (traceNew && index(recrest, "MALLOC") > 0)
  {
    if (index(recrest, "Global operator new") > 0)
    {
      rest = stuffafter(recrest, "new allocated ")
      bytes = firstword(rest)
      rest = stuffafter(rest, "bytes at 0x")
      bytesat = firstword(rest)
      if (allocatedseen[bytesat] == "")
      {
        allocatedseen[bytesat] = 1
        allocatedlist[allocatedctr] = bytesat
        allocatedctr++
      }
      allocatedby[bytesat] = newtid
      allocatedtime[bytesat] = newtime
      allocatedbytes[bytesat] = bytes
      allocatedtype[bytesat] = "malloc"
      allocates++
    }
    else if (index(recrest, "Global operator delete") > 0)
    {
      rest = stuffafter(recrest, "delete called for object at 0x")
      bytesat = firstword(rest)
      allocatedby[bytesat] = ""
      frees++
    }
    #MMFS MALLOC: shAlloc: bytesAllocated 88 bytesRequested 24 duration 2 use 1 at 0x323036C8 pool 3 label 'Client'
    else if (index(recrest, "shAlloc: bytesAllocated") > 0)
    {
      rest = stuffafter(recrest, "bytesRequested ")
      bytes = firstword(rest)
      rest = stuffafter(rest, " at 0x")
      bytesat = firstword(rest)
      reqtype = stuffafter(rest, "label '")
      reqtype = substr(reqtype,1,length(reqtype)-1)
      if (allocatedseen[bytesat] == "")
      {
        allocatedseen[bytesat] = 1
        allocatedlist[allocatedctr] = bytesat
        allocatedctr++
      }
      allocatedby[bytesat] = newtid
      allocatedtime[bytesat] = newtime
      allocatedbytes[bytesat] = bytes
      allocatedtype[bytesat] = reqtype
    }
    #MMFS MALLOC: Freeing memory at 0x4078B340 back to pool 2
    else if (index(recrest, "Freeing memory") > 0)
    {
      rest = stuffafter(recrest, "Freeing memory at 0x")
      bytesat = firstword(rest)
      allocatedby[bytesat] = ""
    }
    #(obsolete)MMFS MALLOC: Freeing storage at 0x34F20B40 back to pool 3
    else if (index(recrest, "Freeing storage") > 0)
    {
      rest = stuffafter(recrest, "Freeing storage at 0x")
      bytesat = firstword(rest)
      allocatedby[bytesat] = ""
    }
  }

  if (traceMsg && ((index(recrest, "msg_id") > 0) || (index(recrest, "verbsServer:") > 0) || (index(recrest, "tscSend") > 0)))
  {
    if (index(recrest, "passing msg to idle worker") > 0) ;
    else if (index(recrest, "service_message: enter") > 0) ;
    else if (index(recrest, "tscSend: service") > 0) {
      # Parse Var recrest " msg '"type"'" rest", msg "
      rest = stuffafter(recrest, " msg '")
      type = firstword(rest)
      rest = stuffafter(rest, type" ")
      pos = index(type, "'")
      if (pos > 0) type = substr(type,1,pos-1)
      pos = index(rest,", msg ")
      if (pos > 0) rest = substr(rest,1,pos-1)
      msgid = stuffafter(rest, "msg_id ")
      msgid = firstword(msgid)
      MSGtime[msgid] = newtime
      MSGtid[msgid] = newtid
      MSGtype[msgid] = type
      MSGmid[newtid] = msgid
      if (details)
        printf("%8d%s %17.9f MSG Send: %s %s\n", newtid, cpusuff, newtime, type, rest)
    }
    else if (index(recrest, "llc_send_msg:") > 0) {
      rest = stuffafter(recrest, "llc_send_msg: ")
      if (details)
        printf("%8d%s %17.9f MSG:      %s\n", newtid, cpusuff, newtime, rest)
    }
    else if (index(recrest, "tscSend: rc") > 0) {
      rest = stuffafter(recrest, " tscSend: rc = ")
      if (rest != "0x00000000" && rest != "0x0") rest = "err="rest
      else rest = ""
      msgid = MSGmid[newtid]
      if (msgid != "")
      {
        delete MSGmid[newtid]
        type = MSGtype[msgid]
        sttime = MSGtime[msgid]
        if (sttime != "")
          delta = (newtime-sttime)*1000000
        else delta = 0
        if (details)
          printf("%8d%s %17.9f MSG FSnd: %s msg_id %d Sduration %.3f us %s\n", newtid, cpusuff, newtime, type, msgid, delta, rest)
        if (delta > 0)
        {
          delta = delta/1000000
          totalsends++
          if (totalsenddelta[type] == 0) minsendbucket[type] = 999999
          totalsenddelta[type] += delta
          totalsend[type]++
          bucket = int(delta / sendbucketsize)
          if (minsendbucket[type] > bucket) minsendbucket[type] = bucket
          if (maxsendbucket[type] < bucket) maxsendbucket[type] = bucket
          sendbuck[bucket]++
          sendbuckets[type,bucket]++
          sendbucketBytes[type,bucket] += MSGReplsize[msgid]
          delete MSGReplsize[msgid]
        }
      }
    }
    else if (index(recrest, "tscSend: replies") > 0) {
      rest = stuffafter(recrest, " tscSend: ")
      if (details)
        printf("%8d%s %17.9f MSG Rerr: %s\n", newtid, cpusuff, newtime, rest)
    }
    else if (index(recrest, "no idle workers; msg queued") > 0)
    {
      # Parse Var recrest " msg '"type"'"rest", msg "
      rest = stuffafter(recrest, " msg '")
      type = firstword(rest)
      rest = stuffafter(rest, type" ")
      pos = index(type, "',")
      if (pos > 0) type = substr(type,1,pos-1)
      pos = index(rest,": msg ")
      if (pos > 0) rest = substr(rest,1,pos-1)
      msgid = stuffafter(recrest, "msg_id ")
      msgid = firstword(msgid)
      msgid = substr(msgid,1,length(msgid)-1)
      MSGQtime[msgid] = newtime
      MSGHtid[msgid] = "msg queued"
      MSGHtype[msgid] = type
      #possibly wrong tid, tscSendReply will set it: MSGHmid[newtid] = msgid
      if (details)
        printf("%8d%s %17.9f MSG Qued: %s %s\n", newtid, cpusuff, newtime, type, rest)
    }
    else if (index(recrest, "tscHandleMsg: service") > 0 ||
             index(recrest, "tscHandleMsgDirectly: service") > 0)
    {
      # Parse Var recrest " msg '"type"'"rest", msg "
      rest = stuffafter(recrest, " msg '")
      type = firstword(rest)
      rest = stuffafter(rest, type" ")
      pos = index(type, "',")
      if (pos > 0) type = substr(type,1,pos-1)
      pos = index(rest,", msg ")
      if (pos > 0) rest = substr(rest,1,pos-1)
      msgid = stuffafter(recrest, "msg_id ")
      msgid = firstword(msgid)
      msgid = substr(msgid,1,length(msgid)-1)
      if (MSGHtid[msgid] != "msg queued")
        MSGQtime[msgid] = 0
      if (type == "reply")
        type = type" "MSGHtype[msgid]
      else
      {
        MSGHtime[msgid] = newtime
        MSGHtid[msgid] = newtid
        MSGHtype[msgid] = type
        #possibly wrong tid, tscSendReply will set it: MSGHmid[newtid] = msgid
      }
      replylen = stuffafter(recrest, ", len ")
      MSGReplsize[msgid] += firstword(replylen)+0
      if (details)
        printf("%8d%s %17.9f MSG Recv: %s %s\n", newtid, cpusuff, newtime, type, rest)
    }
    else if (index(recrest, "verbsServer:   enter") > 0) {
      rdmaStart[newtid] = newtime
      rest = stuffafter(recrest, "enter ")
      rdwr = firstword(rest)
      msgid = firstword(stuffafter(rest, " tag "))
      if (rdwr == "WR")      # pretend this was a getData RPC starting
      {
        if (details)
          printf("%8d%s %17.9f MSG Send: RDMAgetData msg_id %d %s\n", newtid, cpusuff, newtime, msgid, rest)
      }
    }
    else if (index(recrest, "verbsServer:    exit") > 0) {
      if (rdmaStart[newtid] == "")
        delete rdmaStart[newtid]
      else
      {
        rest = stuffafter(recrest, "exit ")
        rdwr = firstword(rest)
        msgid = firstword(stuffafter(rest, " tag "))
        if (rdwr == "RD")      # leave data for tscSendReply: service
          rdmaCount[newtid] = $NF
        else if (rdwr == "WR") # pretend this was a getData RPC ending
        {
          replylen = $NF
          type = "RDMAgetData"
          qtime = 0
          sttime = rdmaStart[newtid]
          delta = (newtime-sttime)*1000000
          if (details)
            printf("%8d%s %17.9f MSG FSnd: %s msg_id %d Sduration %.3f us Rlen %d %s\n",
                   newtid, cpusuff, newtime, type, msgid, delta, replylen, rest)
          if (delta > 0)
          {
            delta = delta/1000000
            totalsends++
            if (totalsenddelta[type] == 0) minsendbucket[type] = 999999
            totalsenddelta[type] += delta
            totalsend[type]++
            bucket = int(delta / sendbucketsize)
            if (minsendbucket[type] > bucket) minsendbucket[type] = bucket
            if (maxsendbucket[type] < bucket) maxsendbucket[type] = bucket
            sendbuck[bucket]++
            sendbuckets[type,bucket]++
            sendbucketBytes[type,bucket] += replylen
          }
          delete rdmaStart[newtid]
        }
      }
    }
    else if (index(recrest, "tscSendReply: service") > 0) {
      # Parse Var recrest ", msg '"type"'" rest", msg "
      rest = stuffafter(recrest, ", msg '")
      type = firstword(rest)
      rest = stuffafter(rest, type" ")
      pos = index(type, "',")
      if (pos > 0) type = substr(type,1,pos-1)
      msgid = stuffafter(rest, "msg_id ")
      msgid = firstword(msgid)
      msgid = substr(msgid,1,length(msgid)-1)
      MSGHmid[newtid] = msgid
      if (rdmaStart[newtid] > 0)
      {
        MSGReplsize[msgid] = rdmaCount[newtid]
        MSGRepltime[msgid] = rdmaStart[newtid]
        delete rdmaCount[newtid]
      }
      else
      {
        replylen = stuffafter(rest, "replyLen ")
        MSGReplsize[msgid] = firstword(replylen)+0
        MSGRepltime[msgid] = newtime
      }
      if (details)
        printf("%8d%s %17.9f MSG Repl: %s %s\n", newtid, cpusuff, newtime, type, rest)
    }
    else if (index(recrest, "tscSendReply1:") > 0) {
      rest = stuffafter(recrest, "tscSendReply1: err = ")
      if (rest != 0) rest = "err="rest
      else rest = ""
      msgid = MSGHmid[newtid]
      if (msgid != "")
      {
        delete MSGHmid[newtid]
        type = MSGHtype[msgid]
        qtime = MSGQtime[msgid]
        sttime = MSGHtime[msgid]
        srtime = MSGRepltime[msgid]
        if (qtime != 0)
          qdelta = (newtime-qtime)*1000000
        else qdelta = 0
        if (sttime != "")
          delta = (newtime-sttime)*1000000
        else delta = 0
        if (srtime != "")
          rdelta = (newtime-srtime)*1000000
        else rdelta = 0
        if (details)
          printf("%8d%s %17.9f MSG FRep: %s msg_id %d Rduration %.3f us Rlen %d Hduration %.3f us Qduration %.3f us %s\n",
                 newtid, cpusuff, newtime, type, msgid, rdelta, MSGReplsize[msgid], delta, qdelta, rest)
        if (qdelta+delta > 0)
        {
          delta = (qdelta+delta)/1000000
          totalhands++
          if (totalhanddelta[type] == 0) minhandbucket[type] = 999999
          totalhanddelta[type] += delta
          totalhand[type]++
          bucket = int(delta / handbucketsize)
          if (minhandbucket[type] > bucket) minhandbucket[type] = bucket
          if (maxhandbucket[type] < bucket) maxhandbucket[type] = bucket
          handbuck[bucket]++
          handbuckets[type,bucket]++
          handbucketBytes[type,bucket] += MSGReplsize[msgid]
        }
        if (type == "nsdMsgRead" && rdelta > 0)
        {
          # treat reply time as a send for nsdMsgRead
          if (rdmaStart[newtid] > 0)
            type="nsdMsgRead(RDMAputData)"
          else
            type="nsdMsgRead(putData)"
          rdelta = rdelta/1000000
          totalsends++
          if (totalsenddelta[type] == 0) minsendbucket[type] = 999999
          totalsenddelta[type] += rdelta
          totalsend[type]++
          bucket = int(rdelta / sendbucketsize)
          if (minsendbucket[type] > bucket) minsendbucket[type] = bucket
          if (maxsendbucket[type] < bucket) maxsendbucket[type] = bucket
          sendbuck[bucket]++
          sendbuckets[type,bucket]++
          sendbucketBytes[type,bucket] += MSGReplsize[msgid]
        }
        delete MSGReplsize[msgid]
      }
      else if (details)
        printf("%8d%s %17.9f MSG FRep: %s %s\n", newtid, cpusuff, newtime, type, rest)
      delete rdmaStart[newtid]
    }
    else {
      rest = stuffafter(recrest, "TS: ")
      if (details && rest != "")
        printf("%8d%s %17.9f MSG: %s\n", newtid, cpusuff, newtime, rest)
    }
  }

  if (traceMutex && index(recrest, "MUTEX") > 0)
  {
    if (index(recrest, "waiting for mute") > 0)
    {
      timest[newtid]=newtime
      $0=substr($0,index($0, "waiting for mute"));
      mutexst[newtid]=$4
      typest[newtid]=getmutextype(5)
    }
    else if (index(recrest, "Waiting for mute") > 0)
    {
      timest[newtid]=newtime
      $0=substr($0,index($0, "Waiting for mute"))
      mutexst[newtid]=$4
      typest[newtid]=getmutextype(5)
    }
    else if (index(recrest, "Acquired mutex") > 0)
    {
      $0=substr($0,index($0, "Acquired mutex"))
      mutex=$3
      type=getmutextype(4)
      mutexholder[mutex] = newtid
      mutexholdtim[mutex] = newtime
      if (mutexDetails)
        printf("%8d%s %17.9f MUTEX Acq: %15.9f %15s %15s   %s %s\n", newtid, cpusuff, newtime, newtime, "Holding", "-", mutex, type )
    }
    else if (index(recrest, "Releasing mutex") > 0)
    {
      $0=substr($0,index($0, "Releasing mutex"))
      mutex=$3
      type=getmutextype(4)
      if (mutexholder[mutex] == newtid)
      {
        delta = 1000*(newtime-mutexholdtim[mutex])
        holdercnt[mutex" "type]++
        totholdtime[mutex" "type] += delta
        if (mutexDetails)
          printf("%8d%s %17.9f MUTEX Rel: %15s %15.9f %15.9fms %s %s\n", newtid, cpusuff, newtime, "Releasing", newtime, delta, mutex, type )
      }
      else
        if (mutexDetails)
          printf("%8d%s %17.9f MUTEX Rel: %15s %15.9f %15s   %s %s\n", newtid, cpusuff, newtime, "Releasing", newtime, "-", mutex, type )
      delete mutexholder[mutex]
    }
    else if (index(recrest, "now owns mutex") > 0)
    {
      $0=substr($0,index($0, "now owns mutex"))
      mutex=$4
      type=getmutextype(5)
      mutexholder[mutex] = newtid
      mutexholdtim[mutex] = newtime
      if (timest[newtid] != "")
      {
        delta=1000*(newtime-timest[newtid])
        if (mutexDetails)
          printf("%8d%s %17.9f MUTEX Own: %15.9f %15.9f %15.9fms %s %s\n", newtid, cpusuff, newtime, timest[newtid], newtime, delta, mutex, type )
        delete timest[newtid]
        dwaiters[mutex" "type]++
        dwaiterstim[mutex" "type]+=delta
      }
      else
        if (mutexDetails)
          printf("%8d%s %17.9f MUTEX Own: %15s %15.9f %15s   %s %s\n", newtid, cpusuff, newtime, "***", newtime, "*awoken*", mutex, type )
    }
    else if (index(recrest, "Awakened after wait") > 0)
    {
      $0=substr($0,index($0, "Awakened after wait"))
      mutex=$6
      type=getmutextype(7)
      if (timest[newtid] != "")
      {
        delta=1000*(newtime-timest[newtid])
        if (mutexDetails)
          printf("%8d%s %17.9f MUTEX Awa: %15.9f %15.9f %15.9fms %s %s\n", newtid, cpusuff, newtime, timest[newtid], newtime, delta, mutex, type)
        delete timest[newtid]
        kwaiters[mutex" "type]++
        kwaiterstim[mutex" "type]+=delta
      }
      else
        if (mutexDetails)
          printf("%8d%s %17.9f MUTEX Awa: %15s %15.9f %15s   %s %s\n", newtid, cpusuff, newtime, "***", newtime, "*awoken*", mutex, type)
    }
  }

  if (traceCond && index(recrest, "condvar") > 0)
  {
    cond = firstword(stuffafter(recrest, "condvar "))
    wcount = firstword(stuffafter(recrest, "waitCount "))
    if (cond != "")
    {
      if (index(recrest,"decremented") > 0)
      {
        waitCount[cond] -= 1
        if (seenCond[cond] == "")
        {
          waitCount[cond] = wcount
          seenCond[cond] = cond
        }
        else if (details && waitCount[cond] != wcount)
          printf("%8d%s %17.9f CONDVAR: %s wake  count %s does not match calc count %d\n",
                 newtid, cpusuff, newtime, cond, wcount, waitCount[cond])
      }
      else if (index(recrest,"incremented") > 0)
      {
        waitCount[cond] += 1
        if (seenCond[cond] == "")
        {
          waitCount[cond] = wcount
          seenCond[cond] = cond
        }
        else if (details && waitCount[cond] != wcount)
          printf("%8d%s %17.9f CONDVAR: %s wait  count %s does not match calc count %d\n",
                 newtid, cpusuff, newtime, cond, wcount, waitCount[cond])
      }
      else if (index(recrest,"roadcasting") > 0 || index(recrest,"ignalling") > 0)
      {
        if (index(recrest,"no waiters") > 0) wcount = 0
        if (seenCond[cond] == "")
        {
          waitCount[cond] = wcount
          seenCond[cond] = cond
        }
        else if (waitCount[cond] != wcount)
          printf("%8d%s %17.9f CONDVAR: %s bcast count %s does not match calc count %d\n",
                 newtid, cpusuff, newtime, cond, wcount, waitCount[cond])
      }
    }
  }
}

/SSA DASD / {
  rec = $0
  if (cpucol > 0)
  {
    newcpu = firstword(substr($0, cpucol, 6))
    cpusuff = sprintf(":%-2d", newcpu)
  }
  else
    newcpu = oldcpu
  if (tidcol > 0)
    newtid = firstword(substr($0, tidcol))
  else
    newtid = oldtid[newcpu]
  if (timecol > 0)
  {
    newtime = firstword(substr($0, timecol))
    if (addtime > 0) newtime += addtime
    if (tickfactor > 1 && newtime != "")
      newtime = newtime * tickfactor
  }

  rest = stuffafter($0, "SSA DASD ")

  if (traceIO)
  {
    if (index(rest, "bstart:") > 0)
    {
      # SSA DASD bstart: hdisk2 bp=52B8E520 pblock=838EC00 bcount=40000 B_WRITE
      disk = firstword(stuffafter(rest,"bstart: "))
      buffer = firstword(stuffafter(rest,"bp="))
      SSAQIOtime[buffer,disk] = newtime
      SSAQIOtid[buffer,disk] = newtid
      printf("%8d%s %17.9f SSA DASD %s\n", newtid, cpusuff, newtime, rest)
    }
    else if (index(rest, "iodone:") > 0)
    {
      # SSA DASD iodone: hdisk4 bp=52B8E520
      disk = firstword(stuffafter(rest,"iodone: "))
      buffer = firstword(stuffafter(rest,"bp="))
      if (SSAQIOtime[buffer,disk] != "")
        delta = (newtime-SSAQIOtime[buffer,disk])*1000000
      else delta = 0
      printf("%8d%s %17.9f SSA DASD %s SSAduration %.3f us\n", SSAQIOtid[buffer,disk], cpusuff, newtime, rest, delta)
    }
  }
}


END {
  if (terminate) exit 1

  if (cpucol > 0) cpusuff = "   "
  else cpusuff = ""
  print "\nUnfinished operations:\n"
  for (i = 1; i <= tidcount; i++)
  {
    tid = tids[i]
    for (reqi = reqs[tid]; reqi > 0; reqi--)
      printf("%8d%s ***************** %-20s ************** %s\n", tid, cpusuff, req[tid,reqi], time[tid,reqi])
  }
  if (traceIO)
  {
     for (buffer in QIOtime)
       printf("%8d%s %17.9f *********  Unfinished IO: buffer/disk %s\n", QIOtid[buffer], cpusuff, QIOtime[buffer], buffer)
  }
  if (traceMsg)
  {
    for (tid in MSGmid)
    {
      msgid = MSGmid[tid]
      if ( MSGtime[msgid] != "")
        delta = (newtime-MSGtime[msgid])*1000000
      else delta = 0
      printf("%8d%s %17.9f MSG FSnd: %s msg_id %d Sduration %.3f + us\n", tid, cpusuff, MSGtime[msgid], MSGtype[msgid], msgid, delta)
    }
    for (tid in MSGHmid)
    {
      msgid = MSGHmid[tid]
      if ( MSGHtime[msgid] != "")
        delta = (newtime-MSGHtime[msgid])*1000000
      else delta = 0
      if (MSGRepltime[msgid] != "")
        rdelta = (newtime-MSGRepltime[msgid])*1000000
      else rdelta = 0
      printf("%8d%s %17.9f MSG FRep: %s msg_id %d Rduration %.3f us Rlen %d Hduration %.3f + us\n", tid, cpusuff, MSGRepltime[msgid], type, msgid, rdelta, MSGReplsize[msgid], delta)
    }
  }
  if (traceNew)
  {
    printf("\nUnfreed storage: allocates %d frees %d\n", allocates, frees)
    for (alli = 0; alli < allocatedctr; alli++)
    {
      bytesat = allocatedlist[alli]
      if (allocatedby[bytesat] != "")
        printf("%8d %s alloc 0x%s %d %s\n", allocatedby[bytesat], allocatedtime[bytesat], bytesat, allocatedbytes[bytesat], allocatedtype[bytesat])
    }

    printf("\nUnfreed storage (malloc): allocates %d frees %d\n", allocatesM, freesM)
    for (alli = 0; alli < allocatedctrM; alli++)
    {
      bytesat = allocatedlistM[alli]
      if (allocatedbyM[bytesat] != "")
        printf("%8d %s malloc 0x%s %d %s\n", allocatedbyM[bytesat], allocatedtimeM[bytesat], bytesat, allocatedbytesM[bytesat], allocatedtypeM[bytesat])
    }
  }

  if (numcpu > 0)
    printf("\nElapsed trace time:                              %17.9f seconds on %d cpus\n", newtime, numcpu)
  else
    printf("\nElapsed trace time:                              %17.9f seconds\n", newtime)
  if (tlevel > 0) lastVFStime = newtime
  printf("Elapsed trace time from first VFS call to last:  %17.9f\n",
         lastVFStime-firstVFStime)
  printf("Time idle between VFS calls:                     %17.9f seconds\n", idleVFS)
  printf("\nOperations stats:             total time(s)  count    avg-usecs        wait-time(s)    avg-usecs\n")
  ops=0
  for (treq in timeop)
  {
    ops += cntop[treq]
    if (ruwaitop[treq] > 0)
      printf("  %-20s %17.9f %9d %12.3f ruWait %12.3f %12.3f\n", treq, timeop[treq], cntop[treq], timeop[treq]/cntop[treq]*1000000, ruwaitop[treq], ruwaitop[treq]/cntop[treq]*1000000)
    else
      printf("  %-20s %17.9f %9d %12.3f\n", treq, timeop[treq], cntop[treq], timeop[treq]/cntop[treq]*1000000)
  }
  if (lastVFStime > firstVFStime)
  printf("Ops %9d Secs %17.9f  Ops/Sec %12.3f\n", ops, lastVFStime-firstVFStime-idleVFS, ops/(lastVFStime-firstVFStime-idleVFS))
  printf("\nUser thread stats: GPFS-time(sec)    Appl-time  GPFS-%%  Appl-%%     Ops\n")
  for (tid in timein)
  {
    intm=timein[tid]
    outm=timeout[tid]
    if (intm+outm != 0)
      printf("%10d %17.9f %17.9f %6.2f%% %6.2f%% %7d %s\n", tid, intm, outm, 100*intm/(intm+outm), 100*outm/(intm+outm), tidopcnt[tid], tidname[tid])
    else
      printf("%10d %17.9f %17.9f %6.2f%% %6.2f%% %7d %s\n", tid, intm, outm, 0, 0, tidopcnt[tid], tidname[tid])
  }

  cnt=0
  for (tidstr in totcpu)
  {
    cnt++
    accumcpu += totcpu[tidstr]
    procname = substr(tidstr,index(tidstr," ")+1)
    proccpu[procname] += totcpu[tidstr]
    proctids[procname]++
  }
  if (cnt > 0)
  {
    if (numcpu > 0)
    {
      dispavail = numcpu*newtime
      printf("\nAvailable dispatch time %d cpu * %.9f = %.9f seconds\n", numcpu, newtime, dispavail)
    }
    else
    {
      dispavail = accumcpu
      printf("\nAccumulated dispatch time %.9f seconds\n", accumcpu)
    }
    printf("\nProcess name:                 Dispatched-time(sec)  %%\n")
    for (str in proccpu)
    {
      tcpu = proccpu[str]
      if (proctids[str] > 1)
        namestr=str"*"proctids[str]
      else
        namestr=str
      printf("%27s %17.9f %6.2f%%\n", namestr, tcpu, 100*tcpu/dispavail)
    }
    printf("\nAccumulated CPU             %17.9f %6.2f%% of Available\n", accumcpu, 100*accumcpu/dispavail)
    if (printTIDdispatch)
    {
      printf("\nThread ID:   Dispatched-time(sec)  %% Name\n")
      for (tidstr in totcpu)
      {
        inx = index(tidstr," ")
        tid = substr(tidstr,1,inx-1)
        str = substr(tidstr,inx+1)
        tcpu = totcpu[tidstr]
        printf("%10d %17.9f %6.2f%% %s\n", tid, tcpu, 100*tcpu/dispavail, str)
      }
    }
  }

  if (lockhist && totallockctls > 0)
  {
    print ""
    cnt=0
    printf("# total App-lockctl = %d Average duration = %0.9f sec\n", totallockctls, totallockdelta/totallockctls)
    print "#  time(sec)  count         %     %ile"
    for (i=minlockbucket ; i<=maxlockbucket ; i++)
    {
      j=lockbuckets[i]
      if (j > 0)
      {
        cnt+=j
        printf("%0.6f %10d  %0.6f %0.6f\n",(i+1)*lockbucketsize, j, j/totallockctls, cnt/totallockctls)
      }
    }
  }

  if (IOhist)
  {
    print ""
    if (totalrdwrs > 0)
    {
      cnt=0
      printf("# total App-read/write = %d Average duration = %0.9f sec\n", totalrdwrs, totaldelta/totalrdwrs)
      print "#  time(sec)  count         %     %ile       read      write  avgBytesR  avgBytesW"
      for (i=minreqbucket ; i<=maxreqbucket ; i++)
      {
        if (i in rdbuckets || i in wrbuckets || i in buckets)
        {
          jr=rdbuckets[i]
          jw=wrbuckets[i]
          ju=buckets[i]
          j=jr+jw+ju
          if (j > 0)
          {
            cnt+=j
            if ((jw > 0 && wrbucketBytes[i] > 0) || (jr > 0 && rdbucketBytes[i] > 0))
            {
              if (jr == 0) jrd = 1; else jrd = jr
              if (jw == 0) jwd = 1; else jwd = jw
              printf("%0.6f %10d  %0.6f %0.6f %10d %10d %10d %10d\n",(i+1)*reqbucketsize, j, j/totalrdwrs, cnt/totalrdwrs, jr, jw, rdbucketBytes[i]/jrd, wrbucketBytes[i]/jwd)
            }
            else
              printf("%0.6f %10d  %0.6f %0.6f %10d %10d\n",(i+1)*reqbucketsize, j, j/totalrdwrs, cnt/totalrdwrs, jr, jw)
          }
        }
      }

      if (maxrdwrinprog > 0)
      {
        cnt=0
        print "\n# max concurrant App-read/write = " maxrdwrinprog
        print "# conc    count         %     %ile"
        for (i=0 ; i<=maxrdwrinprog ; i++)
        {
          j=inpbucket[i]
          if (j > 0)
          {
            cnt+=j
            printf("%4d %10d  %0.6f %0.6f\n",i, j, j/totalrdwrs, cnt/totalrdwrs)
          }
        }
      }
    }
    if (totalios > 0)
    {
      printf("\n# IO counts by thread type\n")
      for (t in QIOtype)
        printf("%10d %s\n", QIOtype[t], t)

      printf("\n# total IOs = %d average duration = %0.9f sec\n", totalios, totaliodelta/totalios)
      print "#  time(sec)  count         %     %ile       read      write  avgQdepth  avgBytesR  avgBytesW"
      cnt=0
      for (i=miniobucket ; i<=maxiobucket ; i++)
      {
        if (i in rdiobuckets || i in wriobuckets)
        {
          jr=rdiobuckets[i]
          jw=wriobuckets[i]
          j=jr+jw
          if (j > 0)
          {
            cnt+=j
            if ((jw > 0 && wriobucketBytes[i] > 0) || (jr > 0 && rdiobucketBytes[i] > 0))
            {
              if (jr == 0) jrd = 1; else jrd = jr
              if (jw == 0) jwd = 1; else jwd = jw
              printf("%0.6f %10d  %0.6f %0.6f %10d %10d %10.3f %10d %10d\n",(i+1)*iobucketsize, j, j/totalios, cnt/totalios, jr, jw, iobucketqios[i]/j, rdiobucketBytes[i]/jrd, wriobucketBytes[i]/jwd)
            }
            else
              printf("%0.6f %10d  %0.6f %0.6f %10d %10d %10.3f\n",(i+1)*iobucketsize, j, j/totalios, cnt/totalios, jr, jw, iobucketqios[i]/j)
          }
        }
      }
      for (disk in disklist)
      {
        printf("\n# %s: total IOs = %d average duration = %0.9f sec\n", disk, totaliosD[disk], totaliodeltaD[disk]/totaliosD[disk])
        print "#  time(sec)  count         %     %ile       read      write  avgQdepth  avgBytesR  avgBytesW"
        cnt=0
        for (i=miniobucket ; i<=maxiobucket ; i++)
        {
          if (i in rdiobuckets || i in wriobuckets)
          {
            jr=rdiobucketsD[disk,i]
            jw=wriobucketsD[disk,i]
            delete rdiobucketsD[disk,i]
            delete wriobucketsD[disk,i]
            j=jr+jw
            if (j > 0)
            {
              cnt+=j
              if ((jw > 0 && wriobucketDBytes[disk,i] > 0) || (jr > 0 && rdiobucketDBytes[disk,i] > 0))
              {
                if (jr == 0) jrd = 1; else jrd = jr
                if (jw == 0) jwd = 1; else jwd = jw
                printf("%0.6f %10d  %0.6f %0.6f %10d %10d %10.3f %10d %10d\n",(i+1)*iobucketsize, j, j/totaliosD[disk], cnt/totaliosD[disk], jr, jw, iobucketDqios[disk,i]/j, rdiobucketDBytes[disk,i]/jrd, wriobucketDBytes[disk,i]/jwd)
              }
              else
                printf("%0.6f %10d  %0.6f %0.6f %10d %10d %10.3f\n",(i+1)*iobucketsize, j, j/totaliosD[disk], cnt/totaliosD[disk], jr, jw, iobucketDqios[disk,i]/j)
            }
          }
        }
      }

      printf("\n# total IOs = %d average inter-arrival = %0.9f sec\n", totalios, efftotaliodelta/totalios)
      print "#  time(sec)  count         %     %ile       read      write  avgBytesR  avgBytesW"
      cnt=0
      for (i=miniobucket ; i<=maxiobucket ; i++)
      {
        if (i in effrdiobuckets || i in effwriobuckets)
        {
          jr=effrdiobuckets[i]
          jw=effwriobuckets[i]
          j=jr+jw
          if (j > 0)
          {
            cnt+=j
            if ((jw > 0 && effwriobucketBytes[i] > 0) || (jr > 0 && effrdiobucketBytes[i] > 0))
            {
              if (jr == 0) jrd = 1; else jrd = jr
              if (jw == 0) jwd = 1; else jwd = jw
              printf("%0.6f %10d  %0.6f %0.6f %10d %10d %10d %10d\n",(i+1)*iobucketsize, j, j/totalios, cnt/totalios, jr, jw, effrdiobucketBytes[i]/jrd, effwriobucketBytes[i]/jwd)
            }
            else
              printf("%0.6f %10d  %0.6f %0.6f %10d %10d\n",(i+1)*iobucketsize, j, j/totalios, cnt/totalios, jr, jw)
          }
        }
      }
      for (disk in disklist)
      {
        printf("\n# %s: total IOs = %d average inter-arrival = %0.9f sec\n", disk, totaliosD[disk], efftotaliodeltaD[disk]/totaliosD[disk])
        print "#  time(sec)  count         %     %ile       read      write  avgBytesR  avgBytesW"
        cnt=0
        for (i=miniobucket ; i<=maxiobucket ; i++)
        {
          if (i in effrdiobuckets || i in effwriobuckets)
          {
            jr=effrdiobucketsD[disk,i]
            jw=effwriobucketsD[disk,i]
            delete effrdiobucketsD[disk,i]
            delete effwriobucketsD[disk,i]
            j=jr+jw
            if (j > 0)
            {
              cnt+=j
              if ((jw > 0 && effwriobucketDBytes[disk,i] > 0) || (jr > 0 && effrdiobucketDBytes[disk,i] > 0))
              {
                if (jr == 0) jrd = 1; else jrd = jr
                if (jw == 0) jwd = 1; else jwd = jw
                printf("%0.6f %10d  %0.6f %0.6f %10d %10d %10d %10d\n",(i+1)*iobucketsize, j, j/totaliosD[disk], cnt/totaliosD[disk], jr, jw, effrdiobucketDBytes[disk,i]/jrd, effwriobucketDBytes[disk,i]/jwd)
              }
              else
                printf("%0.6f %10d  %0.6f %0.6f %10d %10d\n",(i+1)*iobucketsize, j, j/totaliosD[disk], cnt/totaliosD[disk], jr, jw)
            }
          }
        }
      }
      if (maxqios > 0)
      {
        cnt=0
        print "\n# max concurrant IOs = " maxqios
        for (i=0 ; i<=maxqios ; i++)
        {
          j=ioinpbucket[i]
          if (j > 0)
          {
            cnt+=j
            printf("%4d %10d  %0.6f %0.6f\n",i, j, j/totalios, cnt/totalios)
          }
        }
        print "\n# disk utilization between firstuse and lastuse     #IOs maxQdepth"
        firstiotime = newtime
        lastiotime = 0
        cntnios = 0
        totidle = 0
        cntdisks = 0
        for (disk in idlediskFirst)
        {
          if (idlediskStart[disk] == 0 )
            idlediskLast[disk] = newtime  # io still going on at end
          diskelap = idlediskLast[disk]-idlediskFirst[disk]
          disknonidle = diskelap-idlediskTime[disk]
          if (diskelap > 0)
          {
            if (firstiotime > idlediskFirst[disk]) firstiotime = idlediskFirst[disk]
            if (lastiotime < idlediskLast[disk]) lastiotime = idlediskLast[disk]
            totidle += idlediskTime[disk]
            cntnios += nios[disk]
            cntdisks++
            if (nios[disk] > 1)
              printf("%s %6.2f%% %s %s %7d %4d\n", disk, 100*disknonidle/diskelap, idlediskFirst[disk], idlediskLast[disk], nios[disk], maxqiosdisk[disk])
            else
              printf("%s         %s %s %7d %4d\n", disk, idlediskFirst[disk], idlediskLast[disk], nios[disk], maxqiosdisk[disk])
          }
        }
        #diskelap = cntdisks*(lastiotime-firstiotime)
        #disknonidle = diskelap-totidle
        #if (diskelap == 0) diskelap=1
        #printf("\nAverage          %6.2f%% %s %s %7d\n", 100*disknonidle/diskelap, firstiotime, lastiotime, cntnios)
      }

      cnt=0
      print "\n# sectors      count         %     %ile       read      write"
      for (i=1; i<=maxSectors;i++)
      {
        if (i in rdsectbucket || i in wrsectbucket)
        {
          jr=rdsectbucket[i]
          jw=wrsectbucket[i]
          j=jr+jw
          if (j > 0)
          {
            cnt+=j
            printf("%9d %10d  %0.6f %0.6f %10d %10d\n",i, j, j/totalios, cnt/totalios, jr, jw)
          }
        }
      }
    }
    print "\n#    time(sec) IO-read     IO-write     App-read    App-write  (MB/s)"
    MBpersec=1/(1000000*timebucketsize)
    for (i=mintimebucket; i<=highbuck;i++)
    {
      if (i in rdsectsum || i in wrsectsum)
      {
        jr=rdsectsum[i]
        jw=wrsectsum[i]
        j=jr+jw
        if (j > 0 || wrbytessum[i] || rdbytessum[i])
          printf("%9.3f %12.3f %12.3f %12.3f %12.3f\n", i*timebucketsize,jr*512*MBpersec, jw*512*MBpersec, rdbytessum[i]*MBpersec, wrbytessum[i]*MBpersec)
      }
    }
  }
  if (traceMsg)
  {
    if (totalsends > 0)
    {
      for (type in totalsend)
      {
        print ""
        cnt=0
        printf("# Send msg %-32s total = %8d   Average duration = %0.9f sec\n", type, totalsend[type], totalsenddelta[type]/totalsend[type])
        print "#  time(sec)  count         %     %ile   avgBytes"
        for (i=minsendbucket[type] ; i<=maxsendbucket[type] ; i++)
        {
          if (i in sendbuck)
          {
            j=sendbuckets[type,i]
            if (j > 0)
            {
              cnt+=j
              jb=sendbucketBytes[type,i]
              if (jb > 0)
                printf("%0.6f %10d  %0.6f %0.6f %10d\n",(i+1)*sendbucketsize, j, j/totalsend[type], cnt/totalsend[type], jb/j)
              else
                printf("%0.6f %10d  %0.6f %0.6f\n",(i+1)*sendbucketsize, j, j/totalsend[type], cnt/totalsend[type])
            }
          }
        }
      }
    }
    if (totalhands > 0)
    {
      for (type in totalhand)
      {
        print ""
        cnt=0
        printf("# Handle msg %-30s total = %8d   Average duration = %0.9f sec\n", type, totalhand[type], totalhanddelta[type]/totalhand[type])
        print "#  time(sec)  count         %     %ile   avgBytes"
        for (i=minhandbucket[type] ; i<=maxhandbucket[type] ; i++)
        {
          if (i in handbuck)
          {
            j=handbuckets[type,i]
            if (j > 0)
            {
              cnt+=j
              jb=handbucketBytes[type,i]
              if (jb > 0)
                printf("%0.6f %10d  %0.6f %0.6f %10d\n",(i+1)*handbucketsize, j, j/totalhand[type], cnt/totalhand[type], jb/j)
              else
                printf("%0.6f %10d  %0.6f %0.6f\n",(i+1)*handbucketsize, j, j/totalhand[type], cnt/totalhand[type])
            }
          }
        }
      }
    }
  }
  if (traceMutex)
  {
    if (mutexDetails)
    {
      print "\n# Outstanding mutex waiters"
      for (tid in timest)
        printf("%8d%s %17.9f MUTEX ***: %15.9f %15s %15.9fms %s %s\n", tid, cpusuff, timest[tid], timest[tid], "*stillwaiting*", 1000*(newtime-timest[tid]), mutexst[tid], typest[tid])
    }
    print "\n# Mutex statistics"
    print "\n    Count  Total Wait(ms)    Avg Wait(ms) Address    Type  (in kernel)"
    for (i in kwaiters)
      printf("%9d %15.9f %15.9f %s\n", kwaiters[i], kwaiterstim[i], kwaiterstim[i]/kwaiters[i], i)
    print "\n    Count  Total Wait(ms)    Avg Wait(ms) Address    Type  (in daemon)"
    for (i in dwaiters)
      printf("%9d %15.9f %15.9f %s\n", dwaiters[i], dwaiterstim[i], dwaiterstim[i]/dwaiters[i], i)
    print "\n    Count  Total Hold(ms)    Avg Hold(ms) Address    Type"
    for (i in holdercnt)
      printf("%9d %15.9f %15.9f %s\n", holdercnt[i], totholdtime[i], totholdtime[i]/holdercnt[i], i)
  }

  print "\n# Lookup results:\n     Inode      Count Name"
  for (inonam in lookups)
  {    
    lookupnamecnt++
    lookupcnt += lookups[inonam]
    pos=index(inonam,SUBSEP)
    inode=substr(inonam,1,pos-1)
    name=substr(inonam,pos+1)
    if (inode == "notfound")
      printf("%10s %10d %s\n",inode,lookups[inonam],name)
    else
      printf("%10d %10d %s\n",inode,lookups[inonam],name)
  }
  printf("# Lookup total: %d lookups on %d names\n",lookupcnt, lookupnamecnt)

}
