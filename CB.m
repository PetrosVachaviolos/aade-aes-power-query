let
    BaseUrl = "https://www1.aade.gr",
    RelativePath = "/tp-api/v2/search",

    Headers = [
        #"Accept" = "application/json, text/plain, */*",
        #"Accept-Encoding" = "gzip, deflate",
        #"Accept-Language" = "EL",
        #"Authorization" = "Bearer " & Token,
        #"Content-Type" = "application/json",
        #"Origin" = "https://www1.aade.gr",
        #"Referer" = "https://www1.aade.gr/tp-web-ui/",
        #"User-Agent" = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
    ],

    // Monthly date ranges for the full year — adjust year as needed
    DateRanges = {
        [dFrom = "2026-01-01T22:00:00", dTo = "2026-01-31T21:59:59"],
        [dFrom = "2026-01-31T22:00:00", dTo = "2026-02-28T21:59:59"],
        [dFrom = "2026-02-28T22:00:00", dTo = "2026-03-31T21:59:59"],
        [dFrom = "2026-03-31T22:00:00", dTo = "2026-04-30T21:59:59"],
        [dFrom = "2026-04-30T22:00:00", dTo = "2026-05-31T21:59:59"],
        [dFrom = "2026-05-31T22:00:00", dTo = "2026-06-30T21:59:59"],
        [dFrom = "2026-06-30T22:00:00", dTo = "2026-07-31T21:59:59"],
        [dFrom = "2026-07-31T22:00:00", dTo = "2026-08-31T21:59:59"],
        [dFrom = "2026-08-31T22:00:00", dTo = "2026-09-30T21:59:59"],
        [dFrom = "2026-09-30T22:00:00", dTo = "2026-10-31T21:59:59"],
        [dFrom = "2026-10-31T22:00:00", dTo = "2026-11-30T21:59:59"],
        [dFrom = "2026-11-30T22:00:00", dTo = "2026-12-31T21:59:59"]
    },

    // Fetch a single page — filtered server-side to status "EX" (exported)
    GetPage = (pageNum as number, dFrom as text, dTo as text) as record =>
        let
            Body = "{#(cr)#(lf)        ""requestedPageNumber"": " & Number.ToText(pageNum) & ",#(cr)#(lf)        ""requestedPageSize"": 50,#(cr)#(lf)        ""declarationStatus"": ""EX"",#(cr)#(lf)        ""submissionDateFrom"": """ & dFrom & """,#(cr)#(lf)        ""submissionDateTo"": """ & dTo & """#(cr)#(lf)    }",
            BodyBinary = Text.ToBinary(Body, TextEncoding.Utf8),
            Resp = Web.Contents(BaseUrl, [
                RelativePath = RelativePath,
                Headers = Headers,
                Content = BodyBinary,
                ManualStatusHandling = {400, 401, 403, 404, 500}
            ]),
            Json = Json.Document(Resp)
        in
            Json,

    // Paginate through all pages for a given date range
    GetAllPagesForRange = (dFrom as text, dTo as text) as list =>
        let
            Pages = List.Generate(
                () => [i = 0, result = GetPage(0, dFrom, dTo)],
                each List.Count(Record.Field(_[result], "content")) > 0,
                each [i = [i] + 1, result = GetPage([i] + 1, dFrom, dTo)],
                each Record.Field(_[result], "content")
            )
        in
            List.Combine(Pages),

    // Collect all pages across all monthly ranges
    AllPages = List.Transform(DateRanges, each GetAllPagesForRange(_[dFrom], _[dTo])),
    AllContent = List.Combine(AllPages),

    // Convert to table and expand all declaration fields
    Table = Table.FromList(AllContent, Splitter.SplitByNothing(), null, null, ExtraValues.Error),
    ExpandedTable = Table.ExpandRecordColumn(Table, "Column1",
        {"id", "operatorId", "applicantTin", "companyTin", "declState", "declarationType",
         "underAmendment", "underInvalidation", "underSupplement", "regimeId", "lrn", "mrn",
         "statusDate", "submissionDate", "receivedDate", "repositoryID",
         "isCalledByRestConsumer", "hasDocuments", "typeCode", "procedureCategory",
         "exporterId", "declarant", "authorizingPartyId", "swpCustomsMessages",
         "goodsItemsInformationList", "isRetrospective"},
        {"id", "operatorId", "applicantTin", "companyTin", "declState", "declarationType",
         "underAmendment", "underInvalidation", "underSupplement", "regimeId", "lrn", "mrn",
         "statusDate", "submissionDate", "receivedDate", "repositoryID",
         "isCalledByRestConsumer", "hasDocuments", "typeCode", "procedureCategory",
         "exporterId", "declarant", "authorizingPartyId", "swpCustomsMessages",
         "goodsItemsInformationList", "isRetrospective"}
    ),

    // Parse date fields
    ChangedType = Table.TransformColumnTypes(ExpandedTable, {
        {"statusDate", type datetimezone},
        {"submissionDate", type datetimezone},
        {"receivedDate", type datetimezone}
    }),
    #"Sorted Rows" = Table.Sort(ChangedType, {{"statusDate", Order.Ascending}}),
    #"Removed Other Columns" = Table.SelectColumns(#"Sorted Rows", {
        "declState", "declarationType", "lrn", "mrn",
        "statusDate", "submissionDate", "receivedDate", "procedureCategory"
    }),

    // Filter to company-specific CB LRN prefixes — replace YOUR_CB_PREFIX and YOUR_CB_PREFIX_ALT with your values
    #"Filtered Rows" = Table.SelectRows(#"Removed Other Columns", each Text.Contains([lrn], "YOUR_CB_PREFIX") or Text.Contains([lrn], "YOUR_CB_PREFIX_ALT")),

    #"Changed Type" = Table.TransformColumnTypes(#"Filtered Rows", {
        {"declState", type text}, {"declarationType", type text},
        {"lrn", type text}, {"mrn", type text},
        {"statusDate", type datetime}, {"submissionDate", type datetime}, {"receivedDate", type datetime}
    }),

    // Normalize alternative prefix to standard prefix for consistent extraction
    #"Replaced Value" = Table.ReplaceValue(#"Changed Type", "YOUR_CB_PREFIX_ALT", "YOUR_CB_PREFIX", Replacer.ReplaceText, {"lrn"}),

    // Extract invoice number — characters after the CB prefix
    #"Extracted LRN" = Table.TransformColumns(#"Replaced Value", {
        {"lrn", each Text.Middle(_, Text.PositionOf(_, "YOUR_CB_PREFIX") + Text.Length("YOUR_CB_PREFIX"), 8), type text}
    }),

    #"Removed Other Columns1" = Table.SelectColumns(#"Extracted LRN", {"declState", "lrn", "mrn", "statusDate"}),
    #"Changed Type1" = Table.TransformColumnTypes(#"Removed Other Columns1", {{"statusDate", type date}}),
    #"Renamed Columns1" = Table.RenameColumns(#"Changed Type1", {{"declState", "Status"}, {"lrn", "Invoice"}, {"mrn", "MRN"}, {"statusDate", "Date"}})
in
    #"Renamed Columns1"
