# DEB-SSH

**仓库目前正在维护，代码已经面目全非**

**警告：安全风险**  
此项目使用`curl | bash`安装方式，可能存在供应链攻击风险（如果GitHub仓库被黑客篡改，脚本可能被恶意修改）。建议先下载脚本审查代码再执行。  
此项目仅适用于非生产环境、爱好者快速设置SSH。如用于生产，请使用更安全的工具。忽略此警告继续使用，即表示您已了解风险。

## 功能一览
自动配置 SSH 公钥

随机目录存储私钥

急速完成-轻松上手

## 立即安装
```
bash <(curl -sSL https://raw.githubusercontent.com/AiLing2416/DEB-SSH/main/install.sh)
```


## 为当前用户自动配置公钥
```
bash <(curl -sSL https://raw.githubusercontent.com/AiLing2416/DEB-SSH/main/keys.sh)
```


## 自动配置端口
### 用法： command + port
```
bash <(curl -sSL https://raw.githubusercontent.com/AiLing2416/DEB-SSH/main/port.sh)
```
