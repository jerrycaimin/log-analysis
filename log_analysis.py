import sys

sys.path.insert(0, "./lib")

import xmltodict
import os
import re
import glob
import time
from datetime import datetime
import csv


# validate and read config file
def read_config(config_file):
    config_fh = open(config_file, "rb").read()
    return xmltodict.parse(config_fh, encoding="utf-8")["root"]


# analyze the log files according to the rules
def analyze_log(config_file, target_path=None, output_file=None):
    if target_path is None:
        target_path = os.getcwd()
    if output_file is None:
        output_file = "./log/result" + time.strftime("%H-%M-%S", time.localtime()) + ".log"
    config = read_config(config_file)

    warning_hittimes = config.get("warning-hittimes", None)
    define_times = config.get("define-times", None)
    issues = config.get("issue", None)

    _parse_issue(target_path, issues, warning_hittimes=warning_hittimes, define_times=define_times,
                 output_file=output_file)


def get_basename(full_path):
    if not full_path:
        return ""

    if full_path.endswith("/") or full_path.endswith("\\"):
        full_path = full_path[:-1]

    return os.path.basename(full_path)


# analyze the log files according to the rules
def refine_log(config_file, target_folders=None, output_file=None):
    output_file = "./log/Log-Refined [" + time.strftime("%Y-%m-%d_%H-%M-%S", time.localtime()) + "].csv"
    csvfile = file(output_file, 'wb')
    writer = csv.writer(csvfile)
    writer.writerow(['datetime', 'filename', 'node', 'log'])

    config = read_config(config_file)
    refine_logs = config.get("refine-log", None)

    if type(refine_logs) != list:
        refine_logs = [refine_logs]

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
                rule = item.get("capture-exps")
                if not rule:
                    continue
                rule = rule.get("exp")
                datetime_exp = item.get("datetime-exp")
                datetime_convertor = item.get("datetime-convertor")

                _write_refine_log(os.path.join(target_folder, filepath), rule, datetime_exp, datetime_convertor,
                                  node_name, writer)


def _write_refine_log(filepath, rule, datetime_exp, datetime_convertor, node_name, writer):
    if type(rule) == list:
        reg_rules = [re.compile(each_rule, re.DOTALL) for each_rule in rule]
    else:
        reg_rules = [re.compile(rule, re.DOTALL)]

    matching_paths = glob.glob(filepath)
    datetime_pattern = re.compile(datetime_exp)

    # import pdb;pdb.set_trace()

    for path in matching_paths:
        # import pdb;pdb.set_trace()
        if os.path.isdir(path):
            print("WARNING: Directory not supported:" + path)
        else:
            lines = open(path, "rb").readlines()
            i = 0
            log_filename = os.path.basename(path)

            while i < len(lines):
                line = lines[i]
                for reg_rule in reg_rules:
                    match = reg_rule.findall(line)
                    # import pdb;pdb.set_trace()
                    if match is not None and len(match) > 0:
                        matched_time = ""
                        match_datetime = datetime_pattern.match(line)
                        if match_datetime:
                            try:
                                matched_time = datetime.strptime(match_datetime.group(1), datetime_convertor)
                                matched_time = matched_time.strftime("\"%Y-%m-%d %H:%M:%S.%f\"")
                            except:
                                matched_time = ""

                        writer.writerow([matched_time, log_filename, node_name, line])
                        break

                i = i + 1
            continue


def _parse_issue(target_path, issues, warning_hittimes=None, define_times=None, output_file=None):
    if output_file is None:
        output_file = "./log/result" + time.strftime("%H-%M-%S", time.localtime()) + ".log"

    if type(issues) != list:
        issues = [issues]

    issue_num = 0
    for issue in issues:
        # import pdb;pdb.set_trace()
        issue_num = issue_num + 1

        counter = 0
        advice = issue.get("advice", "")
        issue_name = issue.get('@name', "")
        print("========Start to check issue%d: %s.==============\n" % (issue_num, issue_name))
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
            for item in items:
                filepath = item.get("filepath")
                if not filepath:
                    filepath = item.get("filepaths")
                    if not filepath:
                        continue
                    filepath = filepath.get("filepath")

                rule = item.get("exp", "")
                # if no exp defined, get all exp from exps tag.
                if not rule:
                    rule = item.get("exps")
                    if not rule:
                        continue
                    rule = rule.get("exp")

                desc = item["desc"]
                print_match_position = False if item.get("print_match_position", "").lower() == "false" else True
                # import pdb;pdb.set_trace()
                log_range = item.get("log_range", "0,0")
                if _regex_rule(target_path, filepath, rule, output_file, desc, log_range, print_match_position):
                    counter += 1

        if define_times is not None:
            if counter >= define_times:
                print("Found the issue.\n\nPlease follow below advice:\n%s.\n" % advice)
                _write_log(output_file,
                           "The issue [" + issue_name + "] is highly happened.\nPlease refer the advice:\n" + advice)
        elif warning_hittimes is not None:
            if counter >= warning_hittimes:
                print(
                "The issue [" + issue_name + "] is probably happened, please check the log to determine. If existed, follow the advice:%s\n" % advice)

        _write_log(output_file,
                   "==================Finish to check issue " + str(issue_num) + ": " + issue_name + "==============")
        _write_log(output_file,
                   "============================================================================================")
        _write_log(output_file, "\n")


def _regex_rule(target_path, filepath, rule, output_file, desc, log_range="0,0", print_match_position=True):
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

    for reg_rule in reg_rules:
        for path in matching_paths:
            # import pdb;pdb.set_trace()
            if os.path.isdir(path):
                print("Only file marched that supported, directory skipped: %s" % path)
            else:
                count = 0
                lines = open(path, "rb").readlines()
                i = 0
                while i < len(lines):
                    count = count + 1
                    line = lines[i]
                    match = reg_rule.findall(line)
                    # import pdb;pdb.set_trace()
                    if match is not None and len(match) > 0:
                        if Is_des_printed == False:
                            _write_log(output_file, "Clue: [" + desc + "]")
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
                            else:
                                _write_log2(output_file, "\t" + print_line)

                            cur_start = cur_start + 1

                        # _write_log(output_file, "------------------")
                        Is_found = True

                    i = i + 1
                continue

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


if __name__ == "__main__":
    config_path = "./config.xml"
    if len(sys.argv) > 1:
        target_folders = sys.argv[1].split("|")
    else:
        target_folders = ["./test"]

    # refine the log from all the dumplogs, which defined in config.xml
    refine_log(config_path, target_folders)

    for target_folder in target_folders:
        if os.path.exists(target_folder):
            basename = get_basename(target_folder)
            output_file = "./log/[" + time.strftime("%Y-%m-%d_%H-%M-%S", time.localtime()) + "]" + basename + ".log"
            # analyze log by each defined task
            analyze_log(config_path, target_folder, output_file)
