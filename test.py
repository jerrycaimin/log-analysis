import csv

csvfile = file('csvtest.csv', 'wb')
writer = csv.writer(csvfile)
writer.writerow(['datetime', 'node', 'log'])
data = [
        ('1', 'http://www.xiaoheiseo.com/', 'xiaohei'),
        ('2', 'http://www.baidu.com/', 'baidu'),
        ('3', 'http://www.jd.com/', 'jingdong')
]
writer.writerows(data)
csvfile.close()