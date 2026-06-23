package payment

import (
	"fmt"
	"strings"
)

// ResolvedRouting 归一化后的支付渠道路由
type ResolvedRouting struct {
	PayType   string
	PayMethod string
}

// ResolveRouting 将 type / pay_method 归一化为渠道与场景
func ResolveRouting(rawType, rawPayMethod string) (*ResolvedRouting, error) {
	normalizedType := normalizePayToken(rawType)
	normalizedMethod := normalizePayMethod(rawPayMethod)

	switch normalizedType {
	case "wx_native", "wechat_native", "native_wx", "native_wechat":
		return buildResolvedRouting("wxpay", "native", normalizedMethod)
	case "wx_h5", "wechat_h5":
		return buildResolvedRouting("wxpay", "h5", normalizedMethod)
	case "wx_jsapi", "wechat_jsapi":
		return buildResolvedRouting("wxpay", "jsapi", normalizedMethod)
	case "alipay_scan", "ali_scan", "alipay_qrcode", "ali_qrcode", "alipay_native", "ali_native":
		return buildResolvedRouting("alipay", "scan", normalizedMethod)
	case "alipay_h5", "ali_h5", "alipay_wap", "ali_wap":
		return buildResolvedRouting("alipay", "h5", normalizedMethod)
	case "alipay_web", "ali_web", "alipay_pc", "ali_pc":
		return buildResolvedRouting("alipay", "web", normalizedMethod)
	case "native", "scan", "qrcode", "h5", "wap", "jsapi", "web", "pc", "precreate":
		if normalizedMethod == "" {
			return nil, fmt.Errorf("type=%s 无法唯一确定支付渠道，请改为传 wxpay/alipay，或使用 wx_native、alipay_scan 这类明确值", rawType)
		}
		return nil, fmt.Errorf("type=%s 仅表示支付场景，不能单独作为支付渠道；请改为传 wxpay/alipay，或使用 wx_native、alipay_scan 这类明确值", rawType)
	case "wxpay", "wechat":
		return buildResolvedRouting("wxpay", defaultPayMethodForProvider("wxpay", normalizedMethod), normalizedMethod)
	case "alipay", "ali":
		return buildResolvedRouting("alipay", defaultPayMethodForProvider("alipay", normalizedMethod), normalizedMethod)
	case "":
		if normalizedMethod == "" {
			return buildResolvedRouting("wxpay", "scan", normalizedMethod)
		}
		if isWechatMethod(normalizedMethod) {
			return buildResolvedRouting("wxpay", normalizedMethod, normalizedMethod)
		}
		if isAlipayMethod(normalizedMethod) {
			return buildResolvedRouting("alipay", normalizedMethod, normalizedMethod)
		}
		return nil, fmt.Errorf("无法根据 pay_method=%s 确定支付渠道，请显式传入 type", rawPayMethod)
	default:
		return buildResolvedRouting(normalizedType, normalizedMethod, normalizedMethod)
	}
}

func buildResolvedRouting(payType, fallbackMethod, explicitMethod string) (*ResolvedRouting, error) {
	method := explicitMethod
	if method == "" {
		method = fallbackMethod
	}
	if method == "" {
		return nil, fmt.Errorf("未识别到支付方式")
	}
	if payType == "alipay" && method == "native" {
		method = "scan"
	}
	return &ResolvedRouting{PayType: payType, PayMethod: method}, nil
}

func normalizePayToken(value string) string {
	replacer := strings.NewReplacer("-", "_", " ", "", ".", "_")
	return strings.ToLower(strings.TrimSpace(replacer.Replace(value)))
}

func normalizePayMethod(value string) string {
	switch normalizePayToken(value) {
	case "", "default":
		return ""
	case "native", "scan", "qrcode", "precreate":
		return "native"
	case "wap", "h5":
		return "h5"
	case "web", "pc", "page":
		return "web"
	case "jsapi":
		return "jsapi"
	default:
		return strings.ToLower(strings.TrimSpace(value))
	}
}

func defaultPayMethodForProvider(payType, payMethod string) string {
	if payMethod != "" {
		return payMethod
	}
	if payType == "alipay" {
		return "scan"
	}
	return "native"
}

func isWechatMethod(payMethod string) bool {
	switch payMethod {
	case "native", "jsapi":
		return true
	default:
		return false
	}
}

func isAlipayMethod(payMethod string) bool {
	switch payMethod {
	case "web":
		return true
	default:
		return false
	}
}

// AppTypeToken 将 pay_method 映射为通道 app_type 中使用的标识
func AppTypeToken(payType, payMethod string) string {
	switch strings.ToLower(strings.TrimSpace(payType)) {
	case "alipay", "ali":
		switch payMethod {
		case "scan", "native":
			return "qrcode"
		case "h5":
			return "wap"
		case "web":
			return "page"
		}
	}
	return payMethod
}

// ResolvePayMethod 将别名或场景值归一化为适配器可识别的 pay_method
func ResolvePayMethod(rawType string) string {
	if routing, err := ResolveRouting(rawType, ""); err == nil {
		return routing.PayMethod
	}
	return normalizePayMethod(rawType)
}
