#!/usr/bin/env python

import sys
import os
#sys.path.insert(0, "./lib")
cur_path = os.path.dirname(os.path.abspath(__file__))
#print cur_path
sys.path.append(cur_path + "/lib")

import xmltodict
import re
import glob
import time
from datetime import datetime
import csv
from optparse import OptionParser
import utils
import commands

from utils import bcolors
yellow_print = bcolors(bcolors.WARNING)
green_print = bcolors(bcolors.OKGREEN)
red_print = bcolors(bcolors.FAIL)


# validate and read config file
def read_config(config_file):
    config_fh = open(config_file, "rb").read()
    return xmltodict.parse(config_fh, encoding="utf-8")["root"]


# analyze the log files according to the rules
def analyze_log(target_path=None, output_file=None):
    if target_path is None:
        target_path = os.getcwd()
    if output_file is None:
        output_file = log_folder + "result.log"

    config_file_num = len(config_files)

    c_f_current = 1
    for config_file in config_files:
        config = read_config(config_file)
        config_name = os.path.basename(config_file)

        warning_hittimes = config.get("warning-hittimes", None)
        define_times = config.get("define-times", None)
        issues = config.get("issue", None)
        user_scripts = config.get("user-scripts", None)

        if config_file_num > 1:
            _write_log(output_file,
                       "############## [" + str(c_f_current) + "/" + str(config_file_num) + "] Analysis for config file " + config_file + ". ##############")
        _parse_issue(config_name, target_path, issues, user_scripts, warning_hittimes=warning_hittimes, define_times=define_times,
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


# TODO Generate env log, need refine
def run_user_script(log_pfolder):
    for config_file in config_files:
        all_scripts_number = 0
        config = read_config(config_file)
        config_name = os.path.basename(config_file)
        mode_name = os.path.splitext(config_name)[0]
        # if not os.path.exists(log_pfolder + "/" + mode_name) and mode_name != "common":
        #     os.mkdir(log_pfolder + "/" + mode_name)

        user_scripts = config.get("user-scripts", None)

        if user_scripts and type(user_scripts) != list:
            user_scripts = [user_scripts]

        if user_scripts:
            cur_num = 1
            all_scripts_number = len(user_scripts)
            if all_scripts_number > 0:
                green_print.printc("    Running scripts in " + config_name)
            for script in user_scripts:
                if not script:
                    continue

                if type(script) == unicode:
                    run_script = script
                else:
                    run_script = script.get("#text")

                if hasattr(script, "get"):
                    script_name = script.get("@name", "script:" + str(cur_num))
                else:
                    script_name = "script:" + str(cur_num)
                print("    [" + str(cur_num) + "/" + str(all_scripts_number) + "] Running script name: " +
                      bcolors.WARNING + script_name + bcolors.ENDC)
                os.system(run_script)
                cur_num = cur_num + 1


# analyze the log files according to the rules
def refine_log(output_file=None, target_folders=None, specified_configs=None):
    if output_file is None:
        output_file = log_folder + "Log-Refined.txt"
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
            if generate_date:
                writer.writerow(['datetime', 'filename', 'node', 'log'])
            else:
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
                    _write_refine_log(target_folder, filepath, exclude_str, rule,
                                      node_name, desc, writer, plane_writer)
    else:
        # plane loop
        for refine_log in refine_logs:
            items = refine_log.get("item", [])

            for item in items:
                desc_print = False
                if not item:
                    continue

                filepath = item.get("filepath")
                exclude_str = item.get("exclude-str")
                desc = item.get("@desc","")
                rule = item.get("capture-exps")
                if not rule:
                    if set_exp:
                        rule = set_exp
                    else:
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
                    _write_refine_log(target_folder, filepath, exclude_str, rule,
                                      node_name, desc, writer, plane_writer)

                if desc:
                    plane_writer.write("===============\n\n")

    if plane_writer:
        plane_writer.close()

        if set_exp:
            print "Refer to file for output:" + output_file

def _write_refine_log(target_folder, filepath, exclude_str, rule, node_name, desc, writer, plane_writer=None):
    if type(rule) == list:
        reg_rules = [re.compile(each_rule, re.DOTALL) for each_rule in rule]
    else:
        reg_rules = [re.compile(rule, re.DOTALL)]

    matching_paths = []
    if type(filepath) == list:
        for f in filepath:
            matching_paths = matching_paths + glob.glob(os.path.join(target_folder, f))
        matching_paths = list(set(matching_paths))
    else:
        matching_paths = glob.glob(os.path.join(target_folder, filepath))
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
            elif f_size > 150000000:
                print "    file size is " + str(f_size) + ", need time to analysis: " + os.path.basename(path)


            # if user limits the start date, do it
            if start_date and plane_writer is None:
                f = utils.NewSeqFile(path, start_date)
                if f.found == False:
                    print "   Warning : [" + start_date + "] not found in " + log_filename + ", will refine by all the file."
            else:
                f = open(path, "rb")

            # if refine_all open, get all the logs
            if refine_all and plane_writer is None:
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
                            if not plane_writer_title and (desc or set_exp):
                                if not set_exp:
                                    print_and_write_line(plane_writer, "[" + node_name + "]", False, True)
                                    plane_writer_title = True
                                else:
                                    print_and_write_line(plane_writer, path, True, True)
                                    plane_writer_title = True

                            if not set_exp:
                                print_and_write_line(plane_writer, "[" + node_name + "]" + line)
                            else:
                                print_and_write_line(plane_writer, "[" + node_name + "]/[" + reg_rule.pattern + "]: " + line, True)
                        else:
                            if generate_date:
                                writer.writerow([_get_datetime_from_line(line),
                                                 log_filename, node_name, line])
                            else:
                                writer.writerow([log_filename, node_name, line])
                        break
            if plane_writer and not set_exp:
                plane_writer.write("\n")
            f.close()

def print_and_write_line(writer, line, is_print=False, add_enter=False):
    if is_print and not silence_grep:
        print line

    if add_enter:
        line = line + "\n"

    writer.write(line)




def _get_datetime_from_line(line):
    if not convertor_map:
        return ""

    for re in convertor_map:
        matched_time = ""
        match_datetime = re.match(line)
        if match_datetime:
            convertors = convertor_map[re]

            if type(convertors) != list:
                convertors = [convertors]

            for conv in convertors:
                try:
                    matched_time = datetime.strptime(match_datetime.group(0), conv)
                    matched_time = matched_time.strftime("\"%Y-%m-%d %H:%M:%S.%f\"")
                    return matched_time
                except:
                    matched_time = ""


def _get_sortable(file_path):
    if not file_path:
        return None;

    sortable = file_path.get("@sortable", False)
    if sortable.lower() == "true":
        sortable = True
    else:
        sortable = False
    return sortable


def _parse_issue(config_name, target_path, issues, user_scripts, warning_hittimes=None, define_times=None, output_file=None):
    if output_file is None:
        output_file = log_folder + "result.log"

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
        if hasattr(advice, "get"):
            advice_name = advice.get("@from", "")
            if advice_name:
                with open(cur_path + "/" + advice_name) as adv_f:
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
                yellow_print.printc("    [WARNING] possibly hit issue: %s" % issue_name)
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

    # if type(user_scripts) != list:
    #     user_scripts = [user_scripts]
    #
    # if user_scripts:
    #     cur_num = 1
    #     all_scripts_number = len(user_scripts)
    #     for script in user_scripts:
    #         if not script:
    #             continue
    #
    #         print("        Start to run user specified scripts for module: [" + config_name + "]")
    #         print("        [" + str(cur_num) + "/" + str(all_scripts_number) + "] Running script: \n" + script)
    #         os.system(script)
    #         cur_num = cur_num + 1



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
    #print file_part
    #import pdb;pdb.set_trace()

    # write rule to tmp file
    reg_tmp_filename = "tmpexp"
    with open(reg_tmp_filename, 'w') as tmpexp:
        if type(rule) == list:
            for r in rule:
                tmpexp.write(r)
        else:
            tmpexp.write(rule)
    #with open("tmpexp") as tmpexp:
    #    print tmpexp.read()

    grep_cmd = "grep -r -f tmpexp " + file_part
    status, output = commands.getstatusoutput(grep_cmd)

    #print status
    #print output

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
                f = utils.NewSeqFile(path, start_date)
            else:
                f = open(path, "rb")
            # skip if larger than 500M
            f_size = os.path.getsize(path)
            if f_size > 300000000:
                print "    file size larger than 300M, is " + str(f_size) + ", use os grep instead to speed up. File:" + os.path.basename(path)
                _regex_rule_grep(target_folder, filepath, sortable, rule, output_file, desc, hint, log_range="0,0", print_match_position=True)
                continue
            elif f_size > 100000000:
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


def addExtraTargetFolders(t_folders):
    added_folders = t_folders + utils.find_folder("smb*")
    added_folders = added_folders + utils.find_folder("nfs*")
    return added_folders


if __name__ == "__main__":
    # config global opt and args
    global start_date
    global refine_all
    global config_files
    global convertor_map
    global generate_date
    global log_folder
    global set_exp
    global silence_grep

    log_pfolder = "./tool_logs/"
    if not os.path.exists(log_pfolder):
        os.mkdir(log_pfolder)
    if os.path.islink(log_pfolder + "latest"):
        os.unlink(log_pfolder + "latest")

    log_folder_name = time.strftime("%Y-%m-%d_%H-%M-%S", time.localtime())
    log_folder = "./tool_logs/" + log_folder_name + "/"

    start_date=None
    refine_all=False
    silence_grep=False
    nodes=""
    set_exp=None

#     if len(sys.argv) > 1:
#         target_folders = sys.argv[1].split("|")
#     else:
#         target_folders = ["./test"]

    usage = "This is gpfs.snap analysis tool that reuse current known solution/knowledge base(under conf/.xml)" + "\n"\
            "to determine the issue and give solution."  + "\n"\
            "Also run the user shell scripts to help analysis per each problem field.(scripts defined in conf/.xml as well)"  + "\n\n"\
            "How to use: cd to unpacked gpfs.snap folder, then run:" + "\n"\
            "    {PATH}/log_analysis.py -m {mode}" + "\n"\
            "    Current support mode:" "\n"\
            "       disk: scan disk related issues," + "\n"\
            "       hang: scan long waiters, hang, deadlock related issues," + "\n"\
            "       network: scan network related issues," + "\n"\
            "       perf: scan performance related issues," + "\n"\
            "       common: scan common issues." + "\n"\
            "Tip: If no mode specifed, all modes under conf/ will be used to check logs."

    parser = OptionParser(usage)
    parser.add_option("-d", "--date", dest="start_date",
                      help="Filter for logs after the date, ex: 2019-07-01 or Sat Feb 25. If not found the string " +
                      "started with the input value, just ignore and search all.")

    # parser.add_option("-a", "--refine-all", dest="refine_all",
    #                   default=False, action="store_true",
    #                   help="ignore capture-exps, refine all logs.")
    #
    # parser.add_option("-g", "--generate-date", dest="generate_date",
    #                   default=False, action="store_true",
    #                   help="generate date when date string includes week not sortable.")

    parser.add_option("-m", "--mode", dest="selected_mode",
                      action="append", help="current supported mode:'common','disk','hang','network','perf'\n" +
                                            "can set multiple mode.")

    # parser.add_option("-c", "--config-file", dest="config_files",
    #                   action="append", help="specify the config files.(Invalid when -m set)")
    #
    # parser.add_option("-f", "--folder", dest="folders",
    #                   action="append", help="specify the folders that need to analysis.")

    parser.add_option("-n", "--nodes", dest="nodes",
                      help="filter the participant nodes by fuzzy matching.")

    # parser.add_option("-e", "--exp", dest="set_exp",
    #                   action="append", help="Can multiply specify what exps to grep in " +
    #                                         "grep-files.xml. If -e specified, only run" +
    #                                         "Refine-Log function.")
    #
    # parser.add_option("-s", "--silence", dest="silence_grep",
    #                   default=False, action="store_true",
    #                   help="If specified, do not print output when use -e to grep.")

    parser.add_option("-s", "--script-only", dest="script_only",
                      default=False, action="store_true",
                      help="Only run scripts, no existing issues check.")

    parser.add_option("-c", "--check-only", dest="check_only",
                      default=False, action="store_true",
                      help="Only check existing issues, no scripts running.")

    (options, args) = parser.parse_args()

    if options.script_only and options.check_only:
        parser.error("options -s and -c are mutually exclusive")

    # get target folder auto
    target_folders = []
    if len(args) > 0:
        if not os.path.exists(args[0]):
            parser.error("target folder not existed:" + args[0])
        target_folders = args[0]
        target_folders = utils.find_file("mmfs.logs*", target_folders, 4)
        target_folders = addExtraTargetFolders(target_folders)

        # del test folder
        target_folders = remove_test_folder(target_folders)
    # elif options.folders:
    #     folders = options.folders
    #     for folder in folders:
    #         if not os.path.exists(folder):
    #             parser.error("target folder not existed:" + folder)
    #         target_folders= target_folders + utils.find_file("mmfs.logs*", folder, 4)
    #     # del duplicate
    #     if target_folders:
    #         target_folders = list(set(target_folders))
    #
    #     target_folders = addExtraTargetFolders(target_folders)
    #     # del test folder
    #     target_folders = remove_test_folder(target_folders)
    else:
        target_folders = utils.find_file("mmfs.logs*", ".", 4)
        target_folders = addExtraTargetFolders(target_folders)
        # del test folder_
        target_folders = remove_test_folder(target_folders)

    # if options.set_exp:
    #     if type(options.set_exp) == list:
    #         set_exp=options.set_exp
    #     else:
    #         set_exp=[options.set_exp]

    # if not options.set_exp:
    # only create log folder when exp notRunning script name: set
    if not os.path.exists(log_folder):
        os.mkdir(log_folder)
    os.system("ln -s " + log_folder_name + " " + log_pfolder + "/latest ")

    # welcome message
    green_print.printc("Welcome to use gpfs.snap analysis tool, this tool will give suggestion to your support \n" +
                       "based on current known issues in logs, as well as running user specified shell scripts to \n" +
                       "generate interested outputs. More help run: log_analysis.py -h")
    print ""
    selected_target_folders = []
    #print folders to be analysis
    if options.nodes:
        nodes_name = options.nodes.split(",")
        # check if specified nodes name in basename
        for node_name in nodes_name:
            for target_folder in target_folders:
                if node_name in get_basename(target_folder):
                    selected_target_folders.append(target_folder)

        len_stf = len(selected_target_folders)
        if len_stf > 0:
            green_print.printc("Node filter string:" + options.nodes + ". Filtered out [" + str(len_stf) +
                               "] nodes that found in total [" + str(len(target_folders)) + "] available targets:")
            for selected_target_folder in selected_target_folders:
                yellow_print.printc(get_basename(selected_target_folder))
            target_folders = selected_target_folders
        else:
            red_print.printc("ERROR: no folder names that contains your options:" + options.nodes + ". Here are all nodes folders:")
            for target_folder in target_folders:
                red_print.printc(get_basename(target_folder))
            sys.exit()
    else:
        print "The following folder(s) contains mmfs.logs, candidates to analysis:"
        for target_folder in target_folders:
            yellow_print.printc(get_basename(target_folder))
    print ""
    #
    # generate_date = options.generate_date
    # if generate_date:
    #     convertor_map = {re.compile("[a-zA-Z]{3} [a-zA-Z]{3}.*?201[5-8]"):["%a %b %d %H:%M:%S.%f %Y",
    #                                                                        "%a %b  %d %H:%M:%S.%f %Y"]}

    #fill in the parameters
    start_date = options.start_date
    # refine_all = options.refine_all
    # silence_grep = options.silence_grep

    # if options.config_files:
    #     config_files = options.config_files
    #     for conf_file in config_files:
    #         if not os.path.exists(conf_file):
    #             parser.error("config file not found, please check the config file again: " + conf_file)
    # elif options.set_exp and not options.config_files:
    #     # only set when user didn't specified config_files, as they might have their own grep-files configured.
    #     config_files = [cur_path + "/grep-files.xml"]
    # else:
    #     config_files = []
    #     for f in os.listdir(cur_path + "/conf"):
    #         config_files.append(cur_path + "/conf/" + f)

    if options.selected_mode:
        #when selected mode set, override config-file settings:
        config_files = []
        if "common" not in options.selected_mode:
            options.selected_mode.append("common")
        for selected_mode in options.selected_mode:
            mode_config_file = cur_path + "/conf/" + selected_mode + ".xml"
            if not os.path.exists(mode_config_file):
                parser.error("mode not supported: " + selected_mode + ", config file not found:" + mode_config_file)
            else:
                config_files.append(mode_config_file)
    else:
        config_files = []
        for f in os.listdir(cur_path + "/conf"):
            config_files.append(cur_path + "/conf/" + f)

    # if not set_exp:
    #     # refine the log from all the dumplogs, which defined in config.xml
    #     print ""
    #     print "######## Refine all " + str(len(target_folders)) + " nodes gpfs.snap into one file ########"
    #     #print "Start to refine the logs from all above folder according to configuration."
    #     if start_date:
    #         print "    : -d is set to " + start_date + ", only extract the logs AFTER this date. (If start date not matched, all data will be generated.)"
    #     if refine_all:
    #         print "    : -a enabled, ignore regex, all the logs from the period will be generated."
    #     if generate_date:
    #         print "    : -g enabled, generate datetime from each line, by which could support time sort, will cost more time."
    #     if options.nodes:
    #         print "    : -n enable, only collect log in folders that name contains " + options.nodes
    #
    #     output_file = log_folder + "Log-Refined.txt"
    #     refine_log(output_file, target_folders)
    #     print "succeeded, refer to output file: " + output_file
    # else:
    #     print "Start to grep " + str(set_exp) + " from files configured in grep-files.xml"
    #     output_fn = ""
    #     for exp in set_exp:
    #         output_fn = output_fn + exp + ","
    #     output_file = "./log/" + output_fn[:-1] + ".txt"
    #     refine_log(output_file, target_folders)
    #     sys.exit()

    # print ""
    # print "######## Generate Environment Report according to  environment-report.xml for all nodes ########"
    # refine_log(log_folder + "environment-report.txt", target_folders, ["./environment-report.xml"])
    # print "succeeded, refer to file: ./log/environment-report.txt"
    # print ""

    if not options.script_only:
        print ""
        green_print.printc("############### Analysing gpfs.snap from existed knowledge ##############")
        analysis_num = 1
        for target_folder in target_folders:
            pre_num = "[" + str(analysis_num) + "/" + str(len(target_folders)) + "]"
            print pre_num + " analysing " + get_basename(target_folder) + " ..."
            if os.path.exists(target_folder):
                basename = get_basename(target_folder)
                output_file = log_folder + basename + ".log"
                # analyze log by each defined task
                analyze_log(target_folder, output_file)
            print "done, output file: " + log_pfolder + "latest/" + basename + ".log"
            analysis_num = analysis_num + 1

    if not options.check_only:
        print ""
        green_print.printc("######## Running user specified scripts ########")
        run_user_script(log_pfolder)
        print ""
        print "All finished."

