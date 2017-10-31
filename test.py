import utils


if __name__== "__main__":
    file_object = open("log\\newf.log", 'a')
    with utils.NewFile("C:\\fs1gs1-ib_1027161535\\mmfs.logs.fs1gs1-ib",
                       "2017-06") as f:
        for line in f:
            file_object.write(line)

    file_object.close()