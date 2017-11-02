import utils
from datetime import datetime
import re

files = utils.find_file("mmfs.logs*","C:\\Logs",5)
print(files)

print "1111e"

#%a %b %d %X.%f %Y

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