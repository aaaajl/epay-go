package payment

import "testing"

func TestResolveRoutingWXNative(t *testing.T) {
	routing, err := ResolveRouting("WX_NATIVE", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if routing.PayType != "wxpay" || routing.PayMethod != "native" {
		t.Fatalf("got payType=%s payMethod=%s", routing.PayType, routing.PayMethod)
	}
}

func TestResolveRoutingWxpayWithMethod(t *testing.T) {
	routing, err := ResolveRouting("wxpay", "native")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if routing.PayType != "wxpay" || routing.PayMethod != "native" {
		t.Fatalf("got payType=%s payMethod=%s", routing.PayType, routing.PayMethod)
	}
}

func TestAppTypeTokenAlipayScan(t *testing.T) {
	if got := AppTypeToken("alipay", "scan"); got != "qrcode" {
		t.Fatalf("expected qrcode, got %s", got)
	}
}
