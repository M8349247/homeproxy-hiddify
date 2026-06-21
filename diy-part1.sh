#!/bin/bash

# 源码 = ImmortalWrt 25.12
sed -i 's|https://github.com/coolsnowwolf/lede|https://github.com/immortalwrt/immortalwrt|g' .github/workflows/build.yml
sed -i 's/^CONFIG_BRANCH=.*/CONFIG_BRANCH="openwrt-25.12"/' .github/workflows/build.yml

# homeproxy-hiddify 插件源
echo "src-git hphiddify https://github.com/1andrevich/homeproxy-hiddify.git;main" >> feeds.conf.default
./scripts/feeds update hphiddify
./scripts/feeds install luci-app-homeproxy-hiddify hiddify-core homeproxy-geodata homeproxy-tproxy luci-i18n-homeproxy-zh-cn

# 隐藏系统信息
sed -i 's/DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION="ImmortalWrt"/' package/base-files/files/etc/openwrt_release
sed -i '/DISTRIB_REVISION/d' package/base-files/files/etc/openwrt_release
sed -i '/DISTRIB_TARGET/d' package/base-files/files/etc/openwrt_release
echo "DISTRIB_HOSTNAME='ImmortalWrt'" >> package/base-files/files/etc/openwrt_release

# ==============================================
# 把你的脚本写入开机自启
# ==============================================
cat > /etc/init.d/my_init <<'EOF'
#!/bin/sh

# ==========================================
# 1. 基础信息配置
# ==========================================
root_password="root"
lan_ip_address="10.0.0.1/24"
wlan_name="88888888_5G"
wlan_password="86680352"

# ==========================================
# 2. 设置后台密码
# ==========================================
if [ -n "$root_password" ]; then
  (echo "$root_password"; sleep 1; echo "$root_password") | passwd > /dev/null 2>&1
fi

# ==========================================
# 3. 设置 LAN IP 及 DHCP
# ==========================================
if [ -n "$lan_ip_address" ]; then
  uci set network.lan.ipaddr="$lan_ip_address"
  uci commit network

  uci set dhcp.lan.authoritative='1'
  uci commit dhcp
fi

# ==========================================
# 4. 双频合一 WiFi 配置
# ==========================================
if [ -n "$wlan_name" ] && [ -n "$wlan_password" ] && [ ${#wlan_password} -ge 8 ]; then
  uci set wireless.radio0.disabled='0'
  uci set wireless.radio1.disabled='0'

  cfg_idx=0
  while true; do
    device=$(uci -q get wireless.@wifi-iface[$cfg_idx].device)
    [ -z "$device" ] && break

    uci set wireless.@wifi-iface[$cfg_idx].disabled='0'
    uci set wireless.@wifi-iface[$cfg_idx].device="$device"
    uci set wireless.@wifi-iface[$cfg_idx].encryption='psk2'
    uci set wireless.@wifi-iface[$cfg_idx].ssid="$wlan_name"
    uci set wireless.@wifi-iface[$cfg_idx].key="$wlan_password"

    uci set wireless.@wifi-iface[$cfg_idx].ieee80211k='1'
    uci set wireless.@wifi-iface[$cfg_idx].ieee80211v='1'
    uci set wireless.@wifi-iface[$cfg_idx].bss_transition='1'

    cfg_idx=$((cfg_idx + 1))
  done

  uci commit wireless
fi

# ==========================================
# 5. 双 WAN 口配置
# ==========================================
uci set network.wan.metric='10'
uci set network.wan.defaultroute='1'

for dev in $(uci show network | grep "ports='lan2'" | cut -d'.' -f2 | cut -d'=' -f1 | uniq); do
  uci del_list network."${dev}".ports='lan2' 2>/dev/null
done

uci -q del network.wan1
uci set network.wan1=interface
uci set network.wan1.proto='dhcp'
uci set network.wan1.device='lan2'
uci set network.wan1.metric='20'
uci set network.wan1.auto='1'
uci set network.wan1.defaultroute='0'

uci commit network

# ==========================================
# 6. 防火墙
# ==========================================
uci set firewall.@zone[1].network='wan wan1'
uci set firewall.@defaults.flow_offloading='1'
uci set firewall.@defaults.flow_offloading_hw='0'
uci commit firewall

/etc/init.d/network restart
/etc/init.d/firewall restart

exit 0
EOF

# 赋予权限并设置开机只执行一次
chmod +x /etc/init.d/my_init
/etc/init.d/my_init enable
