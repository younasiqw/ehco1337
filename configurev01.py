import dbus
import json
import requests
'''
-----------------------------------------
Version: 0.1
Author: sjlleo
Description: Ehco Configure Manage Script
-----------------------------------------
'''
def ShowAllRelayConfigs(json_data):
    print("当前有"+str(len(json_data['relay_configs']))+"条中转")
    count = 1
    url = "http://localhost:%d/metrics/?token=%s" % (json_data["web_port"],str(json_data["web_token"]))
    res = requests.get(url).text
    #print(res)
    for k in json_data['relay_configs']:
        Cflag = True
        Bflag = True
        if k['listen_type'] == 'raw':
            print("%d. 中转模式 %s %s --> %s" % (count,k['listen'],k['transport_type'],k['tcp_remotes'][0]), end="")
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
                        bandwidth = float(line[line.find("}")+2:])/1024/1024
                        if bandwidth > 1024:
                            print(" 流量：%.2fGB" % (bandwidth/1024))
                        else:
                            print(" 流量：%.2fMB" % (bandwidth))
            if Bflag:
                print(" 流量：0.00MB")
            count = count + 1
        if k['listen_type'] != 'raw' and k['transport_type'] == 'raw':
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
                        bandwidth = float(line[line.find("}")+2:])/1024/1024
                        if bandwidth > 1024:
                            print(" 流量：%.2fGB" % (bandwidth/1024))
                        else:
                            print(" 流量：%.2fMB" % (bandwidth))
            if Bflag:
                print(" 流量：0.00MB")
            count = count + 1

def DeleteRelayConfigs(json_data, port):
    flag = False
    count = 0
    for k in json_data['relay_configs']:
        if k['listen'].split(":")[1] == str(port):
            flag = True
            json_data['relay_configs'].pop(count)
        count = count + 1
    if not flag:
        print("未找到与端口%s有关的转发"%port)
    if len(json_data['relay_configs']) == 0:
        saveConf(json_data,True)
    else:
        saveConf(json_data)

def ModifyRelayConfigs(json_data, port):
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
    saveConf(json_data)

def saveConf(json_data, flag=False):
    if flag:
        jsonContext = "{\n\"web_port\": 9000,\n\"web_token\": \"leo123leo\",\n\"enable_ping\": false,\n\"relay_configs\":[\n]\n}"
    else:
        jsonContext = json.dumps(json_data,sort_keys=True, indent=4, separators=(',', ':'))
    f2 = open('/usr/local/ehco/ehco.json', 'w')
    f2.write(jsonContext)
    f2.close()

def restartEhcoService():
    sysbus = dbus.SystemBus()
    systemd1 = sysbus.get_object('org.freedesktop.systemd1', '/org/freedesktop/systemd1')
    manager = dbus.Interface(systemd1, 'org.freedesktop.systemd1.Manager')
    job = manager.RestartUnit('ehco.service', 'fail')
    print("重启Ehco服务中...OK")

f = open('/usr/local/ehco/ehco.json')
content = f.read()
json_data = json.loads(content)
ShowAllRelayConfigs(json_data)
print("请选择功能：\n1. 修改转发\n2. 删除转发\n3. 查看转发")
num = eval(input('请选择序号：'))
if num == 1:
    port = input("请输入想要修改的转发的本地端口：")
    ModifyRelayConfigs(json_data, port)
    ShowAllRelayConfigs(json_data)
    restartEhcoService()
elif num == 2:
    port = input("请输入想要删除的转发的本地端口：")
    DeleteRelayConfigs(json_data, port)
    ShowAllRelayConfigs(json_data)
    restartEhcoService()
else:
    ShowAllRelayConfigs(json_data)
