package payment

import (
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

const (
	wechatCertFile = "apiclient_cert.pem"
	wechatKeyFile  = "apiclient_key.pem"
)

// WechatCertOptions 从证书目录构建微信支付 V3 配置所需的业务参数。
type WechatCertOptions struct {
	AppID    string
	MchID    string
	APIv3Key string
}

// ParseCertSerialNo 从 apiclient_cert.pem 内容解析证书序列号（大写十六进制，不含 serial= 前缀）。
func ParseCertSerialNo(certPEM string) (string, error) {
	block, _ := pem.Decode([]byte(certPEM))
	if block == nil {
		return "", fmt.Errorf("invalid certificate PEM")
	}

	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return "", fmt.Errorf("parse certificate: %w", err)
	}

	return strings.ToUpper(cert.SerialNumber.Text(16)), nil
}

// WechatConfigFromCertDir 读取证书目录并生成可用于 NewWechatAdapter 的配置。
func WechatConfigFromCertDir(dir string, opts WechatCertOptions) (*WechatConfig, error) {
	if strings.TrimSpace(opts.AppID) == "" {
		return nil, fmt.Errorf("app_id is required")
	}
	if strings.TrimSpace(opts.MchID) == "" {
		return nil, fmt.Errorf("mch_id is required")
	}
	if strings.TrimSpace(opts.APIv3Key) == "" {
		return nil, fmt.Errorf("api_v3_key is required")
	}

	certPath := filepath.Join(dir, wechatCertFile)
	keyPath := filepath.Join(dir, wechatKeyFile)

	certPEM, err := os.ReadFile(certPath)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", certPath, err)
	}
	keyPEM, err := os.ReadFile(keyPath)
	if err != nil {
		return nil, fmt.Errorf("read %s: %w", keyPath, err)
	}

	serialNo, err := ParseCertSerialNo(string(certPEM))
	if err != nil {
		return nil, err
	}

	return &WechatConfig{
		AppID:      strings.TrimSpace(opts.AppID),
		MchID:      strings.TrimSpace(opts.MchID),
		APIv3Key:   strings.TrimSpace(opts.APIv3Key),
		SerialNo:   serialNo,
		PrivateKey: string(keyPEM),
	}, nil
}

// WechatConfigJSONFromCertDir 返回 JSON 配置，可直接写入通道 config 字段。
func WechatConfigJSONFromCertDir(dir string, opts WechatCertOptions) (json.RawMessage, error) {
	cfg, err := WechatConfigFromCertDir(dir, opts)
	if err != nil {
		return nil, err
	}
	return json.Marshal(cfg)
}
