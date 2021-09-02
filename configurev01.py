import dbus
import json
import requests
import sqlite3
import os


'''
-----------------------------------------
Version: 0.1
Author: sjlleo
Description: Ehco Configure Manage Script
-----------------------------------------
'''

class Settings:
    sqlPath = '/usr/local/ehco/ehcoInfo.db'
    configPath = '/usr/local/ehco/ehco.json'

class colorConst:
    red_prefix='\033[0;31m'
    yellow_prefix='\033[0;33m'
    blue_prefix='\033[0;36m'
    green_prefix='\033[0;32m'
    plain_prefix='\033[0m'

class sqlOperate():
    def __init__(self) -> None:
        self.conn = sqlite3.connect(Settings.sqlPath)

    def initialDataBase(self):
        c = self.conn.cursor()
        c.execute('''CREATE TABLE BandWidth
        (ID INTEGER PRIMARY KEY AUTOINCREMENT,
        ListenPort      CHAR(20)  NOT NULL,
        FlowCount       BIGINT    NOT NULL,
        CycleRule       INT       NOT NULL,
        UpdateTime      TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL);''')
        self.conn.commit()

    '''
    -------------------
    updateData 方法
    用途 数据库校准流量值
    数据来源 ehco 主程序
    -------------------
    参数:
    1. self.conn 数据库连接指针
    2. dataList (list类型) 存放2个元素，第一个元素为端口，第二个元素为流量使用量

    RETURN   (int类型) 为校准过后的流量使用量
 
    '''

    def updateData(self,dataList):
        c = self.conn.cursor()
        # 查找库里面是不是有该端口的流量数据
        cursor = c.execute("SELECT * from BandWidth WHERE ListenPort=%s" % (dataList[0]))

        # 从cursor抓取数据库返回的全部结果集
        result = cursor.fetchall()

        # 因为ehco的每条转发流量使用情况只存放在内存中，每次重启进程会丢失，需要借助数据库实现连续记忆
        if not len(result) == 0:
            for row in result:
                # 如果数据库存储的流量使用量比当前ehco记忆的使用量多，证明ehco被重启过了，将2者数据叠加
                if row[2] > dataList[1]:
                    self.CalibrateBandwidth([dataList[0],int(dataList[1])+int(row[2])])
                    return (int(dataList[1])+int(row[2]))
                else: 
                # 如果ehco记忆的使用量多，ehco则没有中断过，流量的记录是连续的，直接把数据库的流量值更新为ehco当前记忆的流量值
                    self.CalibrateBandwidth([dataList[0],int(dataList[1])])
                    return int(dataList[1])
        else:
            # 兼容无数据库的旧版本脚本，自动将数据插入表中
            c.execute("INSERT INTO BandWidth (ListenPort, FlowCount, CycleRule) \
                VALUES(%s,%s,0)" % (dataList[0],dataList[1]))
            self.conn.commit()
            return int(dataList[1])

    '''
    -------------------
    CalibrateBandwidth 方法
    用途 将校准后的新流量值存入数据库
    -------------------
    参数:
    1. self.conn 数据库连接指针
    2. dlist (list类型) 存放2个元素，第一个元素为端口，第二个元素为流量使用量
 
    '''
    def CalibrateBandwidth(self,dlist):
        c = self.conn.cursor()
        c.execute("UPDATE BandWidth SET FlowCount=%s WHERE ListenPort=%s" % (dlist[0],dlist[1]))
        self.conn.commit()

    def DelRecord(self,ListenPort):
        c = self.conn.cursor()
        c.execute("DELETE FROM BandWidth WHERE ListenPort=%s" % ListenPort)
        self.conn.commit()

    def closeDataBase(self):
        self.conn.close()

class TerminalPanel():
    def __init__(self) -> None:

        # 判断数据库是否存在
        if not os.path.exists(Settings.sqlPath):
            self.DBHandler = sqlOperate()
            # 不存在则初始化数据库
            self.DBHandler.initialDataBase()
        else:
            self.DBHandler = sqlOperate()

        # 读入ehco配置文件地址
        self.config_path = Settings.configPath
        try:
            f = open(self.config_path)
        except Exception:
            print("找不到配置文件，请检查是否正确安装ehco")
            return
        content = f.read()
        # 解析json数据
        json_data = json.loads(content)

        # 将数据可视化
        self.ShowAllRelayConfigs(json_data)
        print("请选择功能：\n1. 添加转发（开发中）\n2. 修改转发\n3. 删除转发")
        num = eval(input('请选择序号：'))
        if num == 1:
            # 添加转发
            pass
        elif num == 2:
            # 修改转发
            port = input("请输入想要修改的转发的本地端口：")
            self.ModifyRelayConfigs(json_data, port)
            self.ShowAllRelayConfigs(json_data)
            self.restartEhcoService()
        elif num == 3:
            # 删除转发
            port = input("请输入想要删除的转发的本地端口：")
            self.DeleteRelayConfigs(json_data, port)
            self.ShowAllRelayConfigs(json_data)
            self.restartEhcoService()
        else:
            self.ShowAllRelayConfigs(json_data)

    '''
    -------------------
    BandwidthShow 方法
    用途 流量格式转换
    -------------------
    参数:
    1. flow (float类型) 流量使用量

    RETURN 转换后的流量值，方便后面打印
 
    '''            
    def BandwidthShow(self,flow):
        flow = flow / 1024 / 1024
        if flow > 1048576:
            return (" 流量：%.2fTB" % (flow/1024))
        elif flow > 1024:
            return (" 流量：%.2fGB" % (flow/1024))
        else:
            return (" 流量：%.2fMB" % (flow))

    '''
    -------------------
    ShowAllRelayConfigs 方法
    用途:
    1. 将从ehco获取的数据重新格式化并使其可视化
    2. 在遍历ehco配置文件的同时更新数据库流量数据
    -------------------
    参数:
    1. json_data (object类型) ehco配置信息

    RETURN 转换后的流量值，方便后面打印
 
    '''   
    def ShowAllRelayConfigs(self,json_data):
        print("当前有"+str(len(json_data['relay_configs']))+"条中转")
        count = 1
        url = "http://localhost:%d/metrics/?token=%s" % (json_data["web_port"],str(json_data["web_token"]))
        try:
            # 尝试从ehco的API获取连接数和流量信息
            res = requests.get(url).text
        except Exception:
            print("W:连接ehco服务端失败，请检查ehco是否正常运行，流量信息将无法正常获取")
            res = ''
        
        # ehco配置文件的转发记录进行遍历（一次循环一条转发记录）
        for k in json_data['relay_configs']:
            # Tips: ehco的API以能简尽简的原则，如果本条转发没有任何连接和流量使用，那么不会显示在API中
            # 如果在ehco的API中找不到有关于本条转发的TCP连接数信息，则为False
            Cflag = True

            # 如果在ehco的API中找不到有关于本条转发的流量使用值信息，则为False
            Bflag = True

            # 收集本条转发记录信息的列表
            Collection = []

            if k['listen_type'] == 'raw':
                Collection.append(k['listen'].split(':')[1])
                print("%d. 中转模式 %s %s --> %s" % (count,k['listen'],k['transport_type'],k['tcp_remotes'][0]), end="")

                # 尝试查找并提取API中的有关本条记录的TCP连接数信息
                for line in res.splitlines():
                    if line.find("ehco_traffic_current_tcp_num{hostname=") == 0:
                        if line.find(k['tcp_remotes'][0]) != -1:
                            print(" TCP连接数："+line[line.find("}")+2:], end="")
                            Cflag = False
                # API中没有找到本条转发的TCP连接数信息，重置为0
                if Cflag:
                    print(" TCP连接数：0", end="")

                # 尝试查找并提取API中的有关本条记录的流量使用值信息
                for line in res.splitlines():
                    if line.find("ehco_traffic_network_transmit_bytes{hostname=") == 0:
                        if line.find(k['tcp_remotes'][0]) != -1:
                            Bflag = False
                            Collection.append(float(line[line.find("}")+2:]))
                # API中没有找到本条转发的流量使用值信息，重置为0
                if Bflag:
                    Collection.append(0)

                count = count + 1
                flowRes = self.DBHandler.updateData(Collection)
                print(self.BandwidthShow(flowRes))


            if k['listen_type'] != 'raw' and k['transport_type'] == 'raw':
                Collection.append(k['listen'].split(':')[1])
                print("%d. 落地模式 %s %s --> %s" % (count,k['listen'],k['listen_type'],k['tcp_remotes'][0]), end="")
                for line in res.splitlines():
                    if line.find("ehco_traffic_current_tcp_num{hostname=") == 0:
                        if line.find(k['tcp_remotes'][0]) != -1:
                            print(" TCP连接数："+line[line.find("}")+2:], end="")
                            Cflag = False
                if Cflag:
                    print(" TCP连接数：0", end="")
                for line in res.splitlines():
                    if line.find("ehco_traffic_network_transmit_bytes{hostname=") == 0:
                        if line.find(k['tcp_remotes'][0]) != -1:
                            Bflag = False
                            Collection.append(float(line[line.find("}")+2:]))
                if Bflag:
                    Collection.append(0)
                count = count + 1
                flowRes = self.DBHandler.updateData(Collection)
                print(self.BandwidthShow(flowRes))


    '''
    -------------------
    DeleteRelayConfigs 方法
    用途 删除中转记录
    -------------------
    参数:
    1. json_data (object类型) ehco配置信息
    2. port 要被删除记录的监听端口

    '''    
    def DeleteRelayConfigs(self,json_data, port):
        flag = False
        count = 0
        for k in json_data['relay_configs']:
            if k['listen'].split(":")[1] == str(port):
                flag = True
                json_data['relay_configs'].pop(count)
            count = count + 1
        if not flag:
            print("未找到与端口%s有关的转发"%port)
        else:
            self.DBHandler.DelRecord(port)
        if len(json_data['relay_configs']) == 0:
            self.saveConf(json_data,True)
        else:
            self.saveConf(json_data)


    '''
    -------------------
    ModifyRelayConfigs 方法
    用途 修改中转记录
    -------------------
    参数:
    1. json_data (object类型) ehco配置信息
    2. port 要被修改记录的监听端口

    '''  
    def ModifyRelayConfigs(self,json_data, port):
        flag = False
        count = 0
        for k in json_data['relay_configs']:
            if k['listen'].split(":")[1] == str(port):
                flag = True
                break
            count = count + 1
        if not flag:
            print("未找到与端口%s有关的转发"%port)
            return
        if k['listen_type'] == 'raw':
            # 中转模式
            remoteIP = input("请输入远程IP地址：")
            remotePort = input("请输入远程远程主机端口：")
            print("请选择传输协议（需与落地一致）：\n1.mwss（稳定性极高且延时最低但传输速率最差）\n2.wss（较好的稳定性及较快的传输速率但延时较高）\n3.raw（无隧道直接转发、效率极高但无抗干扰能力）")
            num = eval(input("输入序号："))
            if num == 1:
                json_data['relay_configs'][count]['transport_type'] = 'mwss'
                json_data['relay_configs'][count]['tcp_remotes'][0] = "wss://" + remoteIP + ":" + remotePort
            elif num == 2:
                json_data['relay_configs'][count]['transport_type'] = 'wss'
                json_data['relay_configs'][count]['tcp_remotes'][0] = "wss://" + remoteIP + ":" + remotePort
            elif num == 3:
                json_data['relay_configs'][count]['transport_type'] = 'raw'
                json_data['relay_configs'][count]['tcp_remotes'][0] = remoteIP + ":" + remotePort
            json_data['relay_configs'][count]['udp_remotes'][0] = remoteIP + ":" + remotePort
        elif k['transport_type'] == 'raw':
            # 落地模式
            remotePort = input("请输入流量目标端口：")
            print("请选择传输协议：\n1.mwss（稳定性极高且延时最低但传输速率最差）\n2.wss（较好的稳定性及较快的传输速率但延时较高）\n3.raw（无隧道直接转发、效率极高但无抗干扰能力）")
            num = eval(input("输入序号（需与中转一致）："))
            if num == 1:
                json_data['relay_configs'][count]['listen_type'] = 'mwss'
            elif num == 2:
                json_data['relay_configs'][count]['listen_type'] = 'wss'
            elif num == 3:
                json_data['relay_configs'][count]['listen_type'] = 'raw'
            json_data['relay_configs'][count]['tcp_remotes'][0] = "0.0.0.0:" + remotePort
            json_data['relay_configs'][count]['udp_remotes'][0] = "0.0.0.0:" + remotePort
        self.saveConf(json_data)

    def saveConf(self,json_data, flag=False):
        if flag:
            jsonContext = "{\n\"web_port\": 9000,\n\"web_token\": \"leo123leo\",\n\"enable_ping\": false,\n\"relay_configs\":[\n]\n}"
        else:
            jsonContext = json.dumps(json_data,sort_keys=True, indent=4, separators=(',', ':'))
        f2 = open(self.config_path, 'w')
        f2.write(jsonContext)
        f2.close()

    def restartEhcoService(self):
        sysbus = dbus.SystemBus()
        systemd1 = sysbus.get_object('org.freedesktop.systemd1', '/org/freedesktop/systemd1')
        manager = dbus.Interface(systemd1, 'org.freedesktop.systemd1.Manager')
        job = manager.RestartUnit('ehco.service', 'fail')
        print("重启Ehco服务中...OK")

TerminalPanel()