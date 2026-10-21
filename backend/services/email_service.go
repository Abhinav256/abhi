package services

import (
	"crypto/tls"
	"fmt"
	"net/smtp"
	"strconv"
	"strings"
)

type EmailService struct {
	host     string
	port     int
	username string
	password string
	from     string
}

func NewEmailService(
	host string,
	port string,
	username string,
	password string,
	from string,
) (*EmailService, error) {
	portNumber, err := strconv.Atoi(port)
	if err != nil {
		return nil, fmt.Errorf("invalid SMTP port: %w", err)
	}

	if strings.TrimSpace(host) == "" {
		return nil, fmt.Errorf("SMTP host is required")
	}

	if strings.TrimSpace(username) == "" {
		return nil, fmt.Errorf("SMTP username is required")
	}

	if strings.TrimSpace(password) == "" {
		return nil, fmt.Errorf("SMTP password is required")
	}

	if strings.TrimSpace(from) == "" {
		return nil, fmt.Errorf("SMTP from address is required")
	}

	return &EmailService{
		host:     host,
		port:     portNumber,
		username: username,
		password: password,
		from:     from,
	}, nil
}

// otpEmailHTML builds a professional HTML email body for OTP verification.
// The OTP is always passed in dynamically — it is never hardcoded here.
func otpEmailHTML(otp string) string {
	// Inline SVG logo (AbhiShare lightning-bolt icon, brand purple #863bff).
	// Using a data URI keeps the email self-contained without any external requests.
	logoSVG := `<svg xmlns="http://www.w3.org/2000/svg" width="40" height="38" fill="none" viewBox="0 0 48 46"><path fill="#863bff" d="M25.946 44.938c-.664.845-2.021.375-2.021-.698V33.937a2.26 2.26 0 0 0-2.262-2.262H10.287c-.92 0-1.456-1.04-.92-1.788l7.48-10.471c1.07-1.497 0-3.578-1.842-3.578H1.237c-.92 0-1.456-1.04-.92-1.788L10.013.474c.214-.297.556-.474.92-.474h28.894c.92 0 1.456 1.04.92 1.788l-7.48 10.471c-1.07 1.498 0 3.579 1.842 3.579h11.377c.943 0 1.473 1.088.89 1.83L25.947 44.94z"/></svg>`

	// Build one table-cell per OTP digit for the large digit display.
	digitCells := ""
	for _, ch := range otp {
		digitCells += fmt.Sprintf(
			`<td style="padding:0 6px;font-family:'Courier New',Courier,monospace;font-size:36px;font-weight:700;letter-spacing:0;color:#1a1a2e;line-height:1;">%c</td>`,
			ch,
		)
	}

	return fmt.Sprintf(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <meta http-equiv="X-UA-Compatible" content="IE=edge"/>
  <title>Your AbhiShare verification code</title>
</head>
<body style="margin:0;padding:0;background-color:#f4f4f8;font-family:'Segoe UI',Helvetica,Arial,sans-serif;">

  <!-- Outer wrapper -->
  <table width="100%%" border="0" cellspacing="0" cellpadding="0" style="background-color:#f4f4f8;">
    <tr>
      <td align="center" style="padding:40px 16px;">

        <!-- Card -->
        <table width="100%%" border="0" cellspacing="0" cellpadding="0"
               style="max-width:520px;background-color:#ffffff;border-radius:16px;
                      box-shadow:0 4px 24px rgba(134,59,255,0.10);overflow:hidden;">

          <!-- ── Logo header ── -->
          <tr>
            <td align="center" style="padding:36px 40px 24px 40px;">
              %s
              <br/>
              <span style="display:inline-block;margin-top:10px;font-size:22px;font-weight:700;
                           color:#1a1a2e;letter-spacing:-0.5px;">AbhiShare</span>
            </td>
          </tr>

          <!-- ── Divider ── -->
          <tr>
            <td style="padding:0 40px;">
              <div style="height:1px;background:linear-gradient(90deg,transparent,#e8e0ff,transparent);"></div>
            </td>
          </tr>

          <!-- ── Heading ── -->
          <tr>
            <td align="center" style="padding:32px 40px 8px 40px;">
              <h1 style="margin:0;font-size:20px;font-weight:700;color:#1a1a2e;letter-spacing:-0.3px;">
                Verify your AbhiShare account
              </h1>
            </td>
          </tr>

          <!-- ── Body text ── -->
          <tr>
            <td align="center" style="padding:8px 40px 24px 40px;">
              <p style="margin:0;font-size:15px;color:#555577;line-height:1.6;">
                Here is your AbhiShare verification code:
              </p>
            </td>
          </tr>

          <!-- ── OTP card ── -->
          <tr>
            <td align="center" style="padding:0 40px 24px 40px;">
              <table border="0" cellspacing="0" cellpadding="0"
                     style="background:linear-gradient(135deg,#f3eeff 0%%,#ede6ff 100%%);
                            border-radius:12px;border:1.5px solid #d8c8ff;
                            width:100%%;max-width:360px;">
                <tr>
                  <td align="center" style="padding:28px 24px 12px 24px;">
                    <p style="margin:0 0 16px 0;font-size:12px;font-weight:600;
                               text-transform:uppercase;letter-spacing:1.5px;color:#863bff;">
                      Verification Code
                    </p>
                    <!-- Digit cells -->
                    <table border="0" cellspacing="0" cellpadding="0" style="margin:0 auto;">
                      <tr>
                        %s
                      </tr>
                    </table>
                  </td>
                </tr>
                <tr>
                  <td align="center" style="padding:12px 24px 24px 24px;">
                    <p style="margin:0;font-size:13px;color:#6644aa;line-height:1.5;">
                      This code is valid for <strong>10&nbsp;minutes</strong> and can only be used once.
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- ── Security notice ── -->
          <tr>
            <td style="padding:0 40px 32px 40px;">
              <table border="0" cellspacing="0" cellpadding="0"
                     style="background-color:#fff8f0;border-radius:8px;
                            border-left:3px solid #f0a020;width:100%%;">
                <tr>
                  <td style="padding:14px 16px;">
                    <p style="margin:0;font-size:13px;color:#7a5500;line-height:1.6;">
                      <strong>Please don't share this code with anyone.</strong><br/>
                      AbhiShare will never ask you for this code.
                    </p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>

          <!-- ── Divider ── -->
          <tr>
            <td style="padding:0 40px;">
              <div style="height:1px;background:#f0ecff;"></div>
            </td>
          </tr>

          <!-- ── Footer ── -->
          <tr>
            <td align="center" style="padding:24px 40px 32px 40px;background-color:#fafafa;border-radius:0 0 16px 16px;">
              <p style="margin:0 0 6px 0;font-size:13px;font-weight:600;color:#863bff;">
                AbhiShare
              </p>
              <p style="margin:0;font-size:12px;color:#aaaacc;line-height:1.6;">
                You're receiving this email because a verification code was<br/>
                requested for your AbhiShare account. If this wasn't you,<br/>
                you can safely ignore this email.
              </p>
              <p style="margin:12px 0 0 0;font-size:11px;color:#ccccdd;">
                &copy; 2026 AbhiShare. All rights reserved.
              </p>
            </td>
          </tr>

        </table>
        <!-- /Card -->

      </td>
    </tr>
  </table>
  <!-- /Outer wrapper -->

</body>
</html>`, logoSVG, digitCells)
}

func (s *EmailService) SendOTP(to string, otp string) error {
	to = strings.TrimSpace(to)
	otp = strings.TrimSpace(otp)

	if to == "" {
		return fmt.Errorf("recipient email is required")
	}

	if otp == "" {
		return fmt.Errorf("OTP is required")
	}

	subject := "Your AbhiShare verification code"

	// Plain-text fallback (shown by email clients that do not render HTML).
	plainText := fmt.Sprintf(
		"Your AbhiShare verification code is: %s\r\n\r\nThis code is valid for 10 minutes and can only be used once.\r\n\r\nPlease don't share this code with anyone. AbhiShare will never ask you for this code.\r\n\r\nIf you did not request this code, you can safely ignore this email.",
		otp,
	)

	htmlBody := otpEmailHTML(otp)

	// Build a multipart/alternative MIME message so email clients that support
	// HTML render the designed template; others fall back to plain text.
	boundary := "AbhiShareBoundary20260101"

	message := strings.Join([]string{
		"From: " + s.from,
		"To: " + to,
		"Subject: " + subject,
		"MIME-Version: 1.0",
		`Content-Type: multipart/alternative; boundary="` + boundary + `"`,
		"",
		"--" + boundary,
		"Content-Type: text/plain; charset=UTF-8",
		"Content-Transfer-Encoding: quoted-printable",
		"",
		plainText,
		"",
		"--" + boundary,
		"Content-Type: text/html; charset=UTF-8",
		"Content-Transfer-Encoding: quoted-printable",
		"",
		htmlBody,
		"",
		"--" + boundary + "--",
	}, "\r\n")

	addr := fmt.Sprintf("%s:%d", s.host, s.port)

	client, err := smtp.Dial(addr)
	if err != nil {
		return fmt.Errorf("failed to connect to SMTP server: %w", err)
	}
	defer client.Close()

	tlsConfig := &tls.Config{
		ServerName: s.host,
		MinVersion: tls.VersionTLS12,
	}

	if ok, _ := client.Extension("STARTTLS"); !ok {
		return fmt.Errorf("SMTP server does not support STARTTLS")
	}

	if err := client.StartTLS(tlsConfig); err != nil {
		return fmt.Errorf("failed to start TLS: %w", err)
	}

	auth := smtp.PlainAuth(
		"",
		s.username,
		s.password,
		s.host,
	)

	if err := client.Auth(auth); err != nil {
		return fmt.Errorf("SMTP authentication failed: %w", err)
	}

	if err := client.Mail(s.from); err != nil {
		return fmt.Errorf("failed to set sender: %w", err)
	}

	if err := client.Rcpt(to); err != nil {
		return fmt.Errorf("failed to set recipient: %w", err)
	}

	writer, err := client.Data()
	if err != nil {
		return fmt.Errorf("failed to open SMTP message: %w", err)
	}

	if _, err := writer.Write([]byte(message)); err != nil {
		_ = writer.Close()
		return fmt.Errorf("failed to write email: %w", err)
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("failed to send email: %w", err)
	}

	if err := client.Quit(); err != nil {
		return fmt.Errorf("failed to close SMTP connection: %w", err)
	}

	return nil
}

func (s *EmailService) SendWelcomeEmail(to string, name string) error {
	to = strings.TrimSpace(to)
	name = strings.TrimSpace(name)

	if to == "" {
		return fmt.Errorf("recipient email is required")
	}

	subject := "Welcome to AbhiShare — Your Account Has Been Created"

	body := fmt.Sprintf(
		"Hello %s,\n\nWelcome to AbhiShare! We are thrilled to have you on board.\n\nYour account has been successfully created with the email address: %s.\n\nThank you for joining us!\n\nBest regards,\nThe AbhiShare Team",
		name, to,
	)

	message := strings.Join([]string{
		"From: " + s.from,
		"To: " + to,
		"Subject: " + subject,
		"MIME-Version: 1.0",
		"Content-Type: text/plain; charset=UTF-8",
		"",
		body,
	}, "\r\n")

	addr := fmt.Sprintf("%s:%d", s.host, s.port)

	client, err := smtp.Dial(addr)
	if err != nil {
		return fmt.Errorf("failed to connect to SMTP server: %w", err)
	}
	defer client.Close()

	tlsConfig := &tls.Config{
		ServerName: s.host,
		MinVersion: tls.VersionTLS12,
	}

	if ok, _ := client.Extension("STARTTLS"); ok {
		if err := client.StartTLS(tlsConfig); err != nil {
			return fmt.Errorf("failed to start TLS: %w", err)
		}
	}

	auth := smtp.PlainAuth(
		"",
		s.username,
		s.password,
		s.host,
	)

	if err := client.Auth(auth); err != nil {
		return fmt.Errorf("SMTP authentication failed: %w", err)
	}

	if err := client.Mail(s.from); err != nil {
		return fmt.Errorf("failed to set sender: %w", err)
	}

	if err := client.Rcpt(to); err != nil {
		return fmt.Errorf("failed to set recipient: %w", err)
	}

	writer, err := client.Data()
	if err != nil {
		return fmt.Errorf("failed to open SMTP message: %w", err)
	}

	if _, err := writer.Write([]byte(message)); err != nil {
		_ = writer.Close()
		return fmt.Errorf("failed to write email: %w", err)
	}

	if err := writer.Close(); err != nil {
		return fmt.Errorf("failed to send email: %w", err)
	}

	if err := client.Quit(); err != nil {
		return fmt.Errorf("failed to close SMTP connection: %w", err)
	}

	return nil
}
