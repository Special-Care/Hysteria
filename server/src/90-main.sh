if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    checkRoot
    case "$1" in
        install|1) echoColor purple "-> 1) 安装 hysteria"; install ;;
        uninstall|2) echoColor purple "-> 2) 卸载 hysteria"; uninstall ;;
        start|3) echoColor purple "-> 3) 启动 hysteria"; start ;;
        stop|4) echoColor purple "-> 4) 暂停 hysteria"; stop ;;
        restart|5) echoColor purple "-> 5) 重新启动 hysteria"; restart ;;
        checkStatus|6) echoColor purple "-> 6) 运行状态"; checkStatus ;;
        updateHysteriaCore|7) echoColor purple "-> 7) 更新Core"; updateHysteriaCore ;;
        generate_client_config|8) echoColor purple "-> 8) 查看当前配置"; generate_client_config ;;
        changeServerConfig|9) echoColor purple "-> 9) 重新配置"; changeServerConfig ;;
        changeIp64|10) echoColor purple "-> 10) 切换ipv4/ipv6优先级"; changeIp64 ;;
        hihyUpdate|11) echoColor purple "-> 11) 更新hihy"; hihyUpdate ;;
        aclControl|12) echoColor purple "-> 12) ACL管理"; aclControl ;;
        getHysteriaTrafic|13) echoColor purple "-> 13) 查看hysteria统计信息"; getHysteriaTrafic ;;
        checkLogs|14) echoColor purple "-> 14) 查看实时日志"; checkLogs ;;
        addSocks5Outbound|15) echoColor purple "-> 15) 添加socks5出站"; addSocks5Outbound ;;
        cronTask) cronTask ;;
        *) menu ;;
    esac
fi
