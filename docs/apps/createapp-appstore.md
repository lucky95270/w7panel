# 通过应用商店新建应用
微擎团队通过长期的运维实践，自行封装了一套应用规范，弥补了目前k8s架构下yaml、helm创建应用的不足，也适配了对传统应用的部署场景。

下面还是以WordPress、MySQL为例，我们将演示一下如何通过应用商店部署应用：

### 安装步骤
1. 首先在应用列表中，找到应用商店入口
   ![image](https://github.com/user-attachments/assets/b0b71f85-491c-4f94-b30f-be68022d6d9f)

2. 然后找到WordPress应用，点击安装
   ![image](https://github.com/user-attachments/assets/9ebdd5a4-d2f7-48ba-b5db-96ea8fcb6485)

3. 初次安装会提示要先安装依赖应用mysql，如果您不使用外部数据库，直接点击安装即可
   ![image](https://github.com/user-attachments/assets/35f0a324-7119-4470-9dd7-f2a3b3e157b9)

4. 安装完成后，配置界面会自动填写mysql的配置信息，然后输入安装域名，直接下一步提交
   ![image](https://github.com/user-attachments/assets/a152d93f-20f7-45f8-8946-9656cba10bb3)

5. 如果域名需要外网访问，请按提示解析域名。如果仅为内网测试，可不用处理，直接管理应用即可完成安装。
   ![image](https://github.com/user-attachments/assets/f50bb2e0-951f-4968-a273-b434f8867b74)


### 访问WordPress
此时数据库已经自动处理，无需再手动创建。域名也在安装时一键配置，访问域名直接进入WordPress即可。
![image](https://github.com/user-attachments/assets/61c849ca-75b3-4236-92bb-5eb73a2fe4f0)
