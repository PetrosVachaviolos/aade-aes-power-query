// Copyright (c) 2026 Petros Vachaviolos. All rights reserved.
// Written by Petros Vachaviolos (sole author), for personal use only. No use or exploitation without
// the author's written permission, also after any employment ends. See LICENSE.txt.
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
