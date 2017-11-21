import utils
from datetime import datetime
import re
# path = "C:\\Logs\\fs1gs1-ib_1027161535\\mmfs.logs.fs1gs1-ib"
# f1 = utils.NewFile(path, "2017-07-20")
# f2 = open(path, "rb")
# 
# f11 = f1.readlines()
# f22 = f2.readlines()
# 
# 
# files = utils.find_file("mmfs.logs*","C:\\Logs",5)
# print(files)
# 
# print "1111e"

#%a %b %d %X.%f %Y

#line = "2017-06-02_14:18:57.279: [E]sdfdsfsdfdsfs"
line = "Wed Jun 21 07:32:00.457 2017:  [E]sdfdsfsdfdsfs"
#line = "2017-02-15_15:30:38.802+0900: [E]sdfdsfsdfdsfs"

convertor_map = {re.compile("[a-zA-Z]{3} [a-zA-Z]{3} .*201[5-8]"):["%a %b %d %H:%M:%S.%f %Y","%a %b %d %H:%M:%S %Z %Y"],
                 re.compile("201[5-8]-.*\+[0-9]{4}"):"%Y-%m-%d_%H:%M:%S.%f%z",
                 re.compile("201[5-8]-.*\.[0-9]{3}"):"%Y-%m-%d_%H:%M:%S.%f"}

convertor_map = {re.compile("[a-zA-Z]{3} [a-zA-Z]{3} .*201[5-8]"):["%a %b %d %H:%M:%S.%f %Y"]}

#ttt = datetime.strptime("Fri Oct 27 16:14:04 JST 2017", "%a %b %d %H:%M:%S JST %Y")
ttt = datetime.strptime("Tue Jul 25 20:00:13.528 2017", "%a %b %d %H:%M:%S.%f %Y")

for re in convertor_map:
    match_datetime = re.match(line)
    if match_datetime:
        convertors = convertor_map[re]
        
        if type(convertors) != list:
            convertors = [convertors]

        for conv in convertors: 
            try:
                matched_time = datetime.strptime(match_datetime.group(0), conv)
                matched_time = matched_time.strftime("\"%Y-%m-%d %H:%M:%S.%f\"")
            except:
                matched_time = ""

matched_time = datetime.strptime("2017-06-02_14:18:57.279", "%Y-%m-%d_%H:%M:%S.%f")
#dt = datetime.now()
print matched_time.strftime("\"%Y-%m-%d %H:%M:%S.%f\"")
                                   
#print matched_time
exit



if __name__== "__main__":
    file_object = open("log\\newf.log", 'a')
    with utils.NewFile("C:\\fs1gs1-ib_1027161535\\mmfs.logs.fs1gs1-ib",
                       "2017-06") as f:
        for line in f:
            file_object.write(line)

    file_object.close()