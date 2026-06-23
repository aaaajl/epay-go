// internal/handler/payment/create.go
package payment

import (
	"context"
	"net/url"
	"strings"

	corepayment "github.com/example/epay-go/internal/payment"
	"github.com/example/epay-go/internal/service"
	"github.com/example/epay-go/pkg/response"
	"github.com/example/epay-go/pkg/sign"
	"github.com/example/epay-go/pkg/utils"
	"github.com/gin-gonic/gin"
	"github.com/shopspring/decimal"
)

// CreateOrderRequest 创建订单请求（兼容原epay）
type CreateOrderRequest struct {
	Pid        string `form:"pid" binding:"required"`         // 商户ID
	Type       string `form:"type" binding:"required"`        // 支付类型
	OutTradeNo string `form:"out_trade_no" binding:"required"`// 商户订单号
	NotifyURL  string `form:"notify_url" binding:"required"`  // 异步通知地址
	ReturnURL  string `form:"return_url"`                     // 同步跳转地址
	Name       string `form:"name" binding:"required"`        // 商品名称
	Money      string `form:"money" binding:"required"`       // 金额
	Sign       string `form:"sign" binding:"required"`        // 签名
	SignType   string `form:"sign_type"`                      // 签名类型
}

// CreateOrder 创建支付订单
func CreateOrder(c *gin.Context) {
	var req CreateOrderRequest
	if err := c.ShouldBind(&req); err != nil {
		response.ParamError(c, "参数错误: "+err.Error())
		return
	}

	merchantService := service.NewMerchantService()
	orderService := service.NewOrderService()

	// 获取商户信息
	merchant, err := merchantService.GetByAPIKey(req.Pid)
	if err != nil {
		response.Error(c, response.CodeParamError, "商户不存在")
		return
	}

	if merchant.Status != 1 {
		response.Error(c, response.CodeForbidden, "商户已被禁用")
		return
	}

	// 验证签名
	params := url.Values{}
	params.Set("pid", req.Pid)
	params.Set("type", req.Type)
	params.Set("out_trade_no", req.OutTradeNo)
	params.Set("notify_url", req.NotifyURL)
	params.Set("name", req.Name)
	params.Set("money", req.Money)
	if req.ReturnURL != "" {
		params.Set("return_url", req.ReturnURL)
	}

	if !sign.VerifyMD5Sign(params, merchant.ApiKey, req.Sign) {
		response.Error(c, response.CodeParamError, "签名验证失败")
		return
	}

	// 解析金额
	amount, err := decimal.NewFromString(req.Money)
	if err != nil || amount.LessThanOrEqual(decimal.Zero) {
		response.ParamError(c, "金额格式错误")
		return
	}

	// 创建订单
	platformBaseURL := getPaymentBaseURL(c)
	orderReq := &service.CreateOrderRequest{
		MerchantID:        merchant.ID,
		OutTradeNo:        req.OutTradeNo,
		Amount:            amount,
		Name:              req.Name,
		PayType:           req.Type,
		NotifyURL:         req.NotifyURL,
		MerchantNotifyURL: req.NotifyURL,
		PlatformBaseURL:   platformBaseURL,
		ReturnURL:         req.ReturnURL,
		ClientIP:          utils.GetClientIP(c),
		PayMethod:         c.DefaultQuery("pay_method", ""),
	}
	if err := orderReq.NormalizeRouting(corepayment.ResolveRouting); err != nil {
		response.ParamError(c, err.Error())
		return
	}

	orderResp, err := orderService.Create(context.Background(), orderReq)
	if err != nil {
		response.Error(c, response.CodeServerError, err.Error())
		return
	}

	response.Success(c, orderResp)
}

func getPaymentBaseURL(c *gin.Context) string {
	scheme := "http"
	if p := c.GetHeader("X-Forwarded-Proto"); p != "" {
		scheme = p
	} else if c.Request.TLS != nil {
		scheme = "https"
	}

	host := strings.TrimSpace(c.Request.Host)
	if host == "" {
		host = "localhost"
	}

	return scheme + "://" + host
}
