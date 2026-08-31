let
    FormBody = "client_id=tp-web-ui-react&username=YOUR_AADE_USERNAME&password=YOUR_AADE_PASSWORD&grant_type=password",

    LoginResponse = Web.Contents(
        "https://www1.aade.gr/auth/realms/trader-portal/protocol/openid-connect/token",
        [
            Headers = [#"Content-Type" = "application/x-www-form-urlencoded"],
            Content = Text.ToBinary(FormBody, TextEncoding.Utf8)
        ]
    ),

    Token = Json.Document(LoginResponse)[access_token]
in
    Token
