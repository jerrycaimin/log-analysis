import sys

sys.path.insert(0, "./lib")

import xmltodict
import os
import re
import glob
import time
from datetime import datetime
import csv
from optparse import OptionParser
import utils 
import commands


# validate and read config file
def read_config(config_file):
    config_fh = open(config_file, "rb").read()
    return xmltodict.parse(config_fh, encoding="utf-8")["root"]


# analyze the log files according to the rules
def analyze_log(target_path=None, output_file=None):
    if target_path is None:
        target_path = os.getcwd()
    if output_file is None:
        output_file = "./log/result" + time.strftime("%H-%M-%S", time.localtime()) + ".log"
    
    config_file_num = len(config_files)
    
    c_f_current = 1
    for config_file in config_files:
        config = read_config(config_file)
    
        warning_hittimes = config.get("warning-hittimes", None)
        define_times = config.get("define-times", None)
        issues = config.get("issue", None)
        
        if config_file_num > 1:
            _write_log(output_file,
                       "############## [" + str(c_f_current) + "/" + str(config_file_num) + "] Analysis for config file " + config_file + ". ##############")
        _parse_issue(target_path, issues, warning_hittimes=warning_hittimes, define_times=define_times,
                     output_file=output_file)
        if config_file_num > 1:
            _write_log(output_file,
                       "############## [" + str(c_f_current) + "/" + str(config_file_num) + "] Finished analysis for config file " + config_file + ". ##############")

        c_f_current = c_f_current + 1

def get_basename(full_path):
    if not full_path:
        return ""

    if full_path.endswith("/") or full_path.endswith("\\"):
        full_path = full_path[:-1]

    return os.path.basename(full_path)


# analyze the log files according to the rules
def refine_log(output_file=None, target_folders=None, specified_configs=None):
    if output_file is None:
        output_file = "./log/Log-Refined [" + time.strftime("%Y-%m-%d_%H-%M-%S", time.localtime()) + "].csv"
    csvfile = file(output_file, 'wb')
    writer = csv.writer(csvfile)
    head_written = False
    plane_writer = None

    refine_logs = []
    
    # for env-report
    if specified_configs:
        op_config_files = specified_configs
    else:
        op_config_files = config_files

    for config_file in op_config_files:
        config = read_config(config_file)
        refine_log = config.get("refine-log", None)
        
        if not refine_log:
            continue
        #any "plane" once, output file is plane
        type = refine_log.get("@type", "csv")
        if type == "plane":
            plane_writer = open(output_file, 'w')
        elif not head_written:
            writer.writerow(['filename', 'node', 'log'])
            head_written = True

        if refine_log:
            refine_logs.append(refine_log)

    if not plane_writer:
        # csv loop
        for target_folder in target_folders:
            node_name = get_basename(target_folder)
            if os.path.exists(target_folder) == False:
                continue
    
            for refine_log in refine_logs:
                items = refine_log.get("item", [])
    
                for item in items:
                    if not item:
                        continue
    
                    filepath = item["filepath"]
                    exclude_str = item.get("exclude-str")
                    rule = item.get("capture-exps")
                    desc = item.get("@desc","")
                    if not rule:
                        rule = ".*"
                    else:
                        rule = rule.get("exp")
                    _write_refine_log(os.path.join(target_folder, filepath), exclude_str, rule,
                                      node_name, desc, writer, plane_writer)
    else:       
        # plane loop
        for refine_log in refine_logs:
            items = refine_log.get("item", [])

            for item in items:
                desc_print = False
                if not item:
                    continue
                
                filepath = item["filepath"]
                exclude_str = item.get("exclude-str")
                rule = item.get("capture-exps")
                desc = item.get("@desc","")
                if not rule:
                    rule = ".*"
                else:
                    rule = rule.get("exp")
                    
                for target_folder in target_folders:
                    node_name = get_basename(target_folder)
                    if os.path.exists(target_folder) == False:
                        continue

                    if desc and not desc_print:
                        plane_writer.write("=====" + desc + "=====\n")
                        desc_print = True
                    _write_refine_log(os.path.join(target_folder, filepath), exclude_str, rule,
                                      node_name, desc, writer, plane_writer)
                    
                if desc:
                    plane_writer.write("===============\n\n")
                
    if plane_writer:
        plane_writer.close()

def _write_refine_log(filepath, exclude_str, rule, node_name, desc, writer, plane_writer=None):
    if type(rule) == list:
        reg_rules = [re.compile(each_rule, re.DOTALL) for each_rule in rule]
    else:
        reg_rules = [re.compile(rule, re.DOTALL)]

    matching_paths = glob.glob(filepath)
    #datetime_pattern = re.compile(datetime_exp)

    # import pdb;pdb.set_trace()

    for path in matching_paths:
        # import pdb;pdb.set_trace()

        # skip exclude_str
        if exclude_str and exclude_str in path:
            continue
        
        if os.path.isdir(path):
            #print("WARNING: Directory not supported:" + path)
            continue
        else:
            log_filename = os.path.basename(path)
            # skip if larger than 600M
            f_size = os.path.getsize(path)
            if f_size > 500000000:
                print "    file size larger than 500M, is " + str(f_size) + ", skip:" + os.path.basename(path)
                continue
            elif f_size > 50000000:
                print "    file size is " + str(f_size) + ", need time to analysis: " + os.path.basename(path)

            
            # if user limits the start date, do it
            if start_date:
                f = utils.NewFile(path, start_date)
                if f.found == False:
                    print "    WARNING: " + start_date + "not found in " + log_filename + ", will refine by all the file."
            else:
                f = open(path, "rb")

            # if refine_all open, get all the logs
            if refine_all:
                reg_rules = [re.compile(".*", re.DOTALL)]

            plane_writer_title = False
            for line in f:
                for reg_rule in reg_rules:
                    match = reg_rule.findall(line)
                    # import pdb;pdb.set_trace()
                    if match is not None and len(match) > 0:
#                         matched_time = ""
#                         match_datetime = datetime_pattern.match(line)
#                         if match_datetime:
#                             try:
#                                 matched_time = datetime.strptime(match_datetime.group(1), datetime_convertor)
#                                 matched_time = matched_time.strftime("\"%Y-%m-%d %H:%M:%S.%f\"")
#                             except:
#                                 matched_time = ""
                        if plane_writer:
                            if not plane_writer_title and desc:
                                plane_writer.write("[" + node_name + "]\n")
                                plane_writer_title = True
                            
                            plane_writer.write(line)
                        else:
                            writer.writerow([log_filename, node_name, line])
                        break
            if plane_writer:
                plane_writer.write("\n")
            f.close()

def _get_sortable(file_path):
    if not file_path:
        return None;

    sortable = file_path.get("@sortable", False)
    if sortable.lower() == "true":
        sortable = True
    else:
        sortable = False
    return sortable

def _parse_issue(target_path, issues, warning_hittimes=None, define_times=None, output_file=None):
    if output_file is None:
        output_file = "./log/result" + time.strftime("%H-%M-%S", time.localtime()) + ".log"

    if type(issues) != list:
        issues = [issues]

    issue_num = 0
    for issue in issues:
        if not issue:
            continue

        # import pdb;pdb.set_trace()
        issue_num = issue_num + 1

        counter = 0
        advice = issue.get("advice", "")
        if hasattr(advice,"get"):
            advice_name = advice.get("@from", "")
            if advice_name:
                with open(advice_name) as adv_f:
                    advice = adv_f.read()
        
        issue_name = issue.get('@name', "")
        #print("========Start to check issue%d: %s.==============\n" % (issue_num, issue_name))
        _write_log(output_file,
                   "============================================================================================")
        _write_log(output_file,
                   "==================Start to check issue " + str(issue_num) + ": " + issue_name + "==============")

        if warning_hittimes is not None:
            warning_hittimes = int(warning_hittimes)

        if define_times is not None:
            define_times = int(define_times)

        items = issue.get("item", None)
        if items is not None:
            if type(items) != list:
                items = [items]

            for item in items:
                filepath = item.get("filepath")
                if not filepath:
                    filepaths = item.get("filepaths")
                    if not filepaths:
                        continue
                    filepath = filepaths.get("filepath")
                    sortable = _get_sortable(filepaths)
                else:
                    sortable = _get_sortable(filepath)
                    
                rule = item.get("exp", "")
                # if no exp defined, get all exp from exps tag.
                if not rule:
                    rule = item.get("exps")
                    if not rule:
                        continue
                    rule = rule.get("exp")

                desc = item["desc"]
                hint = item.get("hint")
                print_match_position = False if item.get("print_match_position", "").lower() == "false" else True
                # import pdb;pdb.set_trace()
                log_range = item.get("log_range", "0,0")
                if _regex_rule(target_path, filepath, sortable, rule, output_file, desc, hint, log_range, print_match_position):
                    counter += 1

        if define_times is not None:
            if counter >= define_times:
                print("    [WARNING] possibly hit issue: %s" % issue_name)
                _write_log(output_file,
                           "The issue [" + issue_name + "] is highly happened.\nPlease refer the advice:\n" + advice)
        elif warning_hittimes is not None:
            if counter >= warning_hittimes:
                no_thing = 0
                #print(
                #"The issue [" + issue_name + "] is probably happened, please check the log to determine. If existed, follow the advice:%s\n" % advice)

        _write_log(output_file,
                   "==================Finish to check issue " + str(issue_num) + ": " + issue_name + "==============")
        _write_log(output_file,
                   "============================================================================================")
        _write_log(output_file, "\n")

def _regex_rule_grep(target_folder, filepath, sortable, rule, output_file, desc, hint, log_range="0,0", print_match_position=True):
    
    file_part = ""
    if type(filepath) == list:
        f_c = 0
        for f in filepath:
            if f_c == 0:
                file_part = os.path.join(target_folder, f)
            else:
                file_part = file_part + " " + os.path.join(target_folder, f)
            f_c = f_c + 1
    else:
        file_part = os.path.join(target_folder, filepath)
    print file_part
    import pdb;pdb.set_trace()
   
    # write rule to tmp file
    reg_tmp_filename = "tmpexp"
    with open(reg_tmp_filename, 'w') as tmpexp:
        if type(rule) == list:
            for r in rule:
                tmpexp.write(r)
        else:
            tmpexp.write(rule)
    with open("tmpexp") as tmpexp:
        print tmpexp.read()
    
    grep_cmd = "grep -r -f tmpexp " + file_part
    status, output = commands.getstatusoutput(grep_cmd)
    
    print status
    print output
    
    Is_des_printed = False
    if status == 0 and len(output) > 0:
        if Is_des_printed == False:
            _write_log(output_file, "Clue: [" + desc + "]")
            if hint:
                _write_log(output_file, "Hint: " + hint)
            _write_log(output_file, "Following related log found:")
            Is_des_printed = True
        _write_log2(output_file, output)
    

def _regex_rule(target_folder, filepath, sortable, rule, output_file, desc, hint, log_range="0,0", print_match_position=True):
    if type(rule) == list:
        reg_rules = [re.compile(each_rule, re.DOTALL) for each_rule in rule]
    else:
        reg_rules = [re.compile(rule, re.DOTALL)]

    matching_paths = []
    if type(filepath) == list:
        for eachfile in filepath:
            matching_paths.extend(glob.glob(os.path.join(target_folder, eachfile)))
    else:
        matching_paths = glob.glob(os.path.join(target_folder, filepath))

    # import pdb;pdb.set_trace()
    Is_found = False
    Is_des_printed = False
    log_ranges = log_range.split(",")
    if len(log_ranges) == 2:
        log_range_start = int(log_ranges[0])
        log_range_end = int(log_ranges[1])
    else:
        log_range_start = 0
        log_range_end = 0

    for path in matching_paths:
        # import pdb;pdb.set_trace()
        if os.path.isdir(path) or os.path.exists(path) == False or os.path.basename(path).endswith("gz"):
            continue
            #print("Only file marched that supported, directory skipped: %s" % path)
        else:
            count = 0
            
            if start_date and sortable:
                f = utils.NewFile(path, start_date)
            else:
                f = open(path, "rb")
            # skip if larger than 500M
            f_size = os.path.getsize(path)
            if f_size > 60000000:
                print "    file size larger than 500M, is " + str(f_size) + ", skip:" + os.path.basename(path)
                _regex_rule_grep(target_folder, filepath, sortable, rule, output_file, desc, hint, log_range="0,0", print_match_position=True)
                continue
            elif f_size > 30000000:
                print "    file size is " + str(f_size) + ", need time to analysis: " + os.path.basename(path)

            #f = open(path, "rb")
            lines = f.readlines()
            i = 0
            found_rule_i = []
            #for line in f:
            while i < len(lines):
                # if found i existed in found_rule_i, skip
                if i in found_rule_i:
                    i = i + 1
                    continue

                count = count + 1
                line = lines[i]
                
                for reg_rule in reg_rules:
                    match = reg_rule.findall(line)
                    # import pdb;pdb.set_trace()
                    if match is not None and len(match) > 0:
                        if Is_des_printed == False:
                            _write_log(output_file, "Clue: [" + desc + "], keyword:[" + reg_rule.pattern + "]")
                            if hint:
                                _write_log(output_file, "Hint: " + hint)
                            _write_log(output_file, "Following related log found:")
                            Is_des_printed = True

                        if print_match_position:
                            _write_log(output_file, "[Line:" + str(count) + "]" + os.path.normpath(path))

                        # import pdb;pdb.set_trace()
                        line_start = i if (i + log_range_start) < 0 else (i + log_range_start)
                        line_end = (len(lines) - 1) if (i + log_range_end) > (len(lines) - 1) else (i + log_range_end)

                        # Able to specified len(lines) at latter parameter in this way:
                        cur_start = line_start
                        for print_line in lines[line_start: line_end + 1]:
                            if cur_start == i and log_range_start != log_range_end:
                                _write_log2(output_file, "------->" + print_line)
                            elif cur_start > i:
                                match_follow = reg_rule.findall(print_line)
                                if match_follow is not None and len(match_follow) > 0:
                                    # append to found rule list
                                    found_rule_i.append(cur_start)
                                    
                                    _write_log2(output_file, "------->" + print_line)
                                else:
                                    _write_log2(output_file, "\t" + print_line)
                            else:
                                _write_log2(output_file, "\t" + print_line)

                            cur_start = cur_start + 1

                        # _write_log(output_file, "------------------")
                        Is_found = True
                        
                        # append to found rule list
                        found_rule_i.append(i)
                i = i + 1
            f.close()

    if Is_found:
        _write_log(output_file, "-----------Finish Clue:[" + desc + "]----------")
        _write_log(output_file, "")
        _write_log(output_file, "")
    return Is_found


def _write_log(filepath, content):
    file_object = open(filepath, 'a')
    file_object.write(content + "\r\n")
    file_object.close()


def _write_log2(filepath, content):
    file_object = open(filepath, 'a')
    file_object.write(content)
    file_object.close()

def remove_test_folder(target_folders):
    # del test folder
    test_folder_tbd = None
    for target_folder in target_folders:
        if get_basename(target_folder) == "test":
            test_folder_tbd = target_folder
            break
    if test_folder_tbd:
        target_folders.remove(test_folder_tbd)

    return target_folders

if __name__ == "__main__":
    # config global opt and args
    global start_date
    global refine_all
    global config_files
    
    start_date=None
    refine_all=False
    
#     if len(sys.argv) > 1:
#         target_folders = sys.argv[1].split("|")
#     else:
#         target_folders = ["./test"]
    
    usage = "usage: %prog [options] arg"  
    parser = OptionParser(usage)  
    parser.add_option("-d", "--date", dest="start_date",  
                      help="logs start from date.")
    
    parser.add_option("-a", "--refine-all", dest="refine_all",
                      default=False, action="store_true",
                      help="ignore capture-exps, refine all logs.")

    parser.add_option("-c", "--config-file", dest="config_files",
                      action="append", help="specify the config files.")
    
    parser.add_option("-f", "--folder", dest="folders",
                      action="append", help="specify the folders that need to analysis.")

    (options, args) = parser.parse_args()
    
    # get target folder auto
    target_folders = []    
    if len(args) > 0:
        if not os.path.exists(args[0]):
            parser.error("target folder not existed:" + args[0])
        target_folders = args[0]
        target_folders = utils.find_file("mmfs.logs*", target_folders, 4)
        
        # del test folder
        target_folders = remove_test_folder(target_folders)
    elif options.folders:
        folders = options.folders
        for folder in folders:
            if not os.path.exists(folder):
                parser.error("targe folder not existed:" + folder)
            target_folders= target_folders + utils.find_file("mmfs.logs*", folder, 4)
        # del duplicate
        if target_folders:
            target_folders = list(set(target_folders))
        
        # del test folder
        target_folders = remove_test_folder(target_folders)
    else:
        target_folders = ["./test"]
    
    #print folders to be analysis
    print "The following folder(s) contains mmfs.logs, candidates to analysis:"
    for target_folder in target_folders:
        print get_basename(target_folder)
    print ""

    #fill in the parameters
    start_date = options.start_date
    refine_all = options.refine_all
    if options.config_files:
        config_files = options.config_files
        for conf_file in config_files:
            if not os.path.exists(conf_file):
                parser.error("config file not found, please check the config file again: " + conf_file)
    else:
        config_files = ["./config.xml"]

    print "############### Analysing gpfs.snap from existed knowledge ##############"
    analysis_num = 1
    for target_folder in target_folders:
        pre_num = "[" + str(analysis_num) + "/" + str(len(target_folders)) + "]"
        print pre_num + " analysing " + get_basename(target_folder) + " ..."
        if os.path.exists(target_folder):
            basename = get_basename(target_folder)
            output_file = "./log/[" + time.strftime("%Y-%m-%d_%H-%M-%S", time.localtime()) + "]" + basename + ".log"
            # analyze log by each defined task
            analyze_log(target_folder, output_file)
        print "done, output file: " + output_file
        analysis_num = analysis_num + 1

    # refine the log from all the dumplogs, which defined in config.xml
    print ""
    print "######## Refine all " + str(len(target_folders)) + " nodes gpfs.snap into one csv (can be sorted or filtered by Excel) ########"
    #print "Start to refine the logs from all above folder according to configuration."
    if start_date:
        print "    : -d is set to " + start_date + ", only extract the logs AFTER this date. (If start date not matched, all data will be generated.)"
    if refine_all:
        print "    : -a enabled, ignore regex, all the logs from the period will be generated."
    
    output_file = "./log/Log-Refined-[" + time.strftime("%Y-%m-%d_%H-%M-%S", time.localtime()) + "].csv"
    refine_log(output_file, target_folders)
    print "succeeded, refer to output file: " + output_file
    
    print ""
    print "######## Generate Environment Report according to  environment-report.xml for all nodes ########"
    refine_log("./log/environment-report.txt", target_folders, ["./environment-report.xml"])
    print "succeeded, refer to file: ./log/environment-report.txt"
    
    print ""
    print "All finished." 
    
