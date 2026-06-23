package payment

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"
	"time"

	"github.com/go-pay/gopay"
	"github.com/go-pay/gopay/wechat/v3"
	"github.com/shopspring/decimal"
)

const defaultWechatCertDir = "1725975775_20260619_cert"

func wechatCertDir(t *testing.T) string {
	t.Helper()

	if dir := strings.TrimSpace(os.Getenv("WECHAT_CERT_DIR")); dir != "" {
		if _, err := os.Stat(filepath.Join(dir, wechatCertFile)); err != nil {
			t.Skipf("WECHAT_CERT_DIR missing %s: %v", wechatCertFile, err)
		}
		return dir
	}

	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("runtime.Caller failed")
	}
	dir := filepath.Join(filepath.Dir(file), "..", "..", "auth", defaultWechatCertDir)
	if _, err := os.Stat(filepath.Join(dir, wechatCertFile)); err != nil {
		t.Skipf("cert dir not found at %s", dir)
	}
	return dir
}

func wechatTestOptions(t *testing.T) WechatCertOptions {
	t.Helper()

	apiV3Key := strings.TrimSpace(os.Getenv("WECHAT_API_V3_KEY"))
	if apiV3Key == "" {
		apiV3Key = strings.TrimSpace(os.Getenv("WECHAT_API_KEY"))
	}

	opts := WechatCertOptions{
		AppID:    strings.TrimSpace(os.Getenv("WECHAT_APP_ID")),
		MchID:    strings.TrimSpace(os.Getenv("WECHAT_MCH_ID")),
		APIv3Key: apiV3Key,
	}
	if opts.AppID == "" {
		opts.AppID = "wx81e9c1c8ad43aad2"
	}
	if opts.MchID == "" {
		opts.MchID = "1725975775"
	}
	if opts.APIv3Key == "" {
		t.Skip("set WECHAT_API_V3_KEY (or WECHAT_API_KEY) to run wechat cert tests")
	}
	return opts
}

func TestParseCertSerialNo(t *testing.T) {
	dir := wechatCertDir(t)
	certPEM, err := os.ReadFile(filepath.Join(dir, wechatCertFile))
	if err != nil {
		t.Fatalf("read cert: %v", err)
	}

	serial, err := ParseCertSerialNo(string(certPEM))
	if err != nil {
		t.Fatalf("ParseCertSerialNo: %v", err)
	}
	if serial != "461D24B83B3DE1AF389687308676E28B81FCABF5" {
		t.Fatalf("unexpected serial: %s", serial)
	}
}

func TestWechatConfigFromCertDir(t *testing.T) {
	dir := wechatCertDir(t)
	opts := wechatTestOptions(t)

	cfg, err := WechatConfigFromCertDir(dir, opts)
	if err != nil {
		t.Fatalf("WechatConfigFromCertDir: %v", err)
	}

	if cfg.SerialNo != "461D24B83B3DE1AF389687308676E28B81FCABF5" {
		t.Fatalf("unexpected serial_no: %s", cfg.SerialNo)
	}
	if cfg.MchID != opts.MchID {
		t.Fatalf("unexpected mch_id: %s", cfg.MchID)
	}
	if cfg.AppID != opts.AppID {
		t.Fatalf("unexpected app_id: %s", cfg.AppID)
	}
	if !strings.Contains(cfg.PrivateKey, "BEGIN PRIVATE KEY") {
		t.Fatal("private_key should contain PEM private key")
	}
	if cfg.APIv3Key != opts.APIv3Key {
		t.Fatal("api_v3_key mismatch")
	}
}

func TestNewWechatAdapterFromCertDir(t *testing.T) {
	dir := wechatCertDir(t)
	opts := wechatTestOptions(t)

	raw, err := WechatConfigJSONFromCertDir(dir, opts)
	if err != nil {
		t.Fatalf("WechatConfigJSONFromCertDir: %v", err)
	}

	adapter, err := NewWechatAdapter(raw)
	if err != nil {
		t.Fatalf("NewWechatAdapter: %v", err)
	}
	if adapter == nil {
		t.Fatal("adapter is nil")
	}
}

func TestWechatNativeOrderSignIntegration(t *testing.T) {
	if os.Getenv("WECHAT_INTEGRATION") != "1" {
		t.Skip("set WECHAT_INTEGRATION=1 to call WeChat API")
	}

	dir := wechatCertDir(t)
	opts := wechatTestOptions(t)

	raw, err := WechatConfigJSONFromCertDir(dir, opts)
	if err != nil {
		t.Fatalf("WechatConfigJSONFromCertDir: %v", err)
	}

	adapter, err := NewWechatAdapter(raw)
	if err != nil {
		t.Fatalf("NewWechatAdapter: %v", err)
	}
	wechatAdapter := adapter.(*WechatAdapter)

	resp, err := wechatAdapter.CreateOrder(context.Background(), &CreateOrderRequest{
		TradeNo:   fmt.Sprintf("SIGNTEST%d", time.Now().UnixNano()),
		Amount:    decimal.NewFromFloat(0.01),
		Subject:   "签名验证测试",
		ClientIP:  "127.0.0.1",
		NotifyURL: "https://pay.wormhole.tech/api/pay/notify/wechat",
		PayMethod: "native",
	})
	if err != nil {
		if strings.Contains(err.Error(), "SIGN_ERROR") {
			t.Fatalf("WeChat SIGN_ERROR — check api_v3_key, serial_no, private_key: %v", err)
		}
		t.Fatalf("CreateOrder: %v", err)
	}
	if resp.PayURL == "" {
		t.Fatal("expected native pay url (code_url)")
	}
}

func TestWechatConfigJSONMatchesChannelFormat(t *testing.T) {
	dir := wechatCertDir(t)
	opts := wechatTestOptions(t)

	raw, err := WechatConfigJSONFromCertDir(dir, opts)
	if err != nil {
		t.Fatalf("WechatConfigJSONFromCertDir: %v", err)
	}

	var payload map[string]string
	if err := json.Unmarshal(raw, &payload); err != nil {
		t.Fatalf("unmarshal config json: %v", err)
	}

	required := []string{"app_id", "mch_id", "api_v3_key", "serial_no", "private_key"}
	for _, key := range required {
		if strings.TrimSpace(payload[key]) == "" {
			t.Fatalf("missing required channel config field %q", key)
		}
	}

	// 管理后台通道 config 应可直接粘贴此 JSON（去掉 private_key 展示时注意安全）。
	t.Logf("channel config serial_no=%s mch_id=%s app_id=%s", payload["serial_no"], payload["mch_id"], payload["app_id"])
}

func TestWechatClientV3DirectSign(t *testing.T) {
	if os.Getenv("WECHAT_INTEGRATION") != "1" {
		t.Skip("set WECHAT_INTEGRATION=1 to call WeChat API")
	}

	dir := wechatCertDir(t)
	opts := wechatTestOptions(t)
	cfg, err := WechatConfigFromCertDir(dir, opts)
	if err != nil {
		t.Fatalf("WechatConfigFromCertDir: %v", err)
	}

	client, err := wechat.NewClientV3(cfg.MchID, cfg.SerialNo, cfg.APIv3Key, cfg.PrivateKey)
	if err != nil {
		t.Fatalf("NewClientV3: %v", err)
	}

	bm := make(gopay.BodyMap)
	bm.Set("appid", cfg.AppID)
	bm.Set("mchid", cfg.MchID)
	bm.Set("description", "签名验证测试")
	bm.Set("out_trade_no", fmt.Sprintf("SIGNCHK%d", time.Now().UnixNano()))
	bm.Set("notify_url", "https://pay.wormhole.tech/api/pay/notify/wechat")
	bm.SetBodyMap("amount", func(b gopay.BodyMap) {
		b.Set("total", 1)
		b.Set("currency", "CNY")
	})

	resp, err := client.V3TransactionNative(context.Background(), bm)
	if err != nil {
		t.Fatalf("V3TransactionNative request failed: %v", err)
	}
	if resp.Code != wechat.Success {
		if strings.Contains(resp.Error, "SIGN_ERROR") {
			t.Fatalf("WeChat SIGN_ERROR: %s", resp.Error)
		}
		t.Fatalf("WeChat API error: %s", resp.Error)
	}
	if resp.Response == nil || resp.Response.CodeUrl == "" {
		t.Fatal("expected code_url in response")
	}
}
