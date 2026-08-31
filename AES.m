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

    // Fetch a single page of results for a given date range
    GetPage = (pageNum as number, dFrom as text, dTo as text) as record =>
        let
            Body = "{#(cr)#(lf)        ""requestedPageNumber"": " & Number.ToText(pageNum) & ",#(cr)#(lf)        ""requestedPageSize"": 50,#(cr)#(lf)        ""submissionDateFrom"": """ & dFrom & """,#(cr)#(lf)        ""submissionDateTo"": """ & dTo & """#(cr)#(lf)    }",
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

    // Exclude rejected and invalidated declarations
    #"Filtered Rows1" = Table.SelectRows(ExpandedTable, each ([declState] <> "Declaration Rejected" and [declState] <> "Invalidated")),

    // Filter to company-specific LRN prefix — replace YOUR_LRN_PREFIX with your value
    #"Filtered Rows2" = Table.SelectRows(#"Filtered Rows1", each Text.Contains([lrn], "YOUR_LRN_PREFIX")),

    // Parse date fields
    ChangedType = Table.TransformColumnTypes(#"Filtered Rows2", {
        {"statusDate", type datetimezone},
        {"submissionDate", type datetimezone},
        {"receivedDate", type datetimezone}
    }),
    #"Changed Type" = Table.TransformColumnTypes(ChangedType, {
        {"declState", type text}, {"declarationType", type text},
        {"lrn", type text}, {"mrn", type text},
        {"statusDate", type datetime}, {"submissionDate", type datetime}, {"receivedDate", type datetime}
    }),

    // Extract invoice number from LRN (between first and second dot)
    #"Extracted Text Between Delimiters" = Table.TransformColumns(#"Changed Type", {{"lrn", each Text.BetweenDelimiters(_, ".", "."), type text}}),

    // Extract procedure category code from parentheses
    #"Extracted Text Between Delimiters1" = Table.TransformColumns(#"Extracted Text Between Delimiters", {{"procedureCategory", each Text.BetweenDelimiters(_, "(", ")"), type text}}),

    // Split statusDate into date and time columns
    #"Split Column by Delimiter" = Table.SplitColumn(
        Table.TransformColumnTypes(#"Extracted Text Between Delimiters1", {{"statusDate", type text}}, "el-GR"),
        "statusDate",
        Splitter.SplitTextByDelimiter(" ", QuoteStyle.Csv),
        {"ΗΜΕΡΟΜΗΝΙΑ", "ΩΡΑ"}
    ),
    #"Changed Type1" = Table.TransformColumnTypes(#"Split Column by Delimiter", {{"ΗΜΕΡΟΜΗΝΙΑ", type date}, {"ΩΡΑ", type time}}),

    // Rename columns to Greek business labels
    #"Renamed Columns" = Table.RenameColumns(#"Changed Type1", {
        {"lrn", "ΤΙΜΟΛΟΓΙΟ"}, {"mrn", "MRN"},
        {"declState", "ΚΑΤΑΣΤΑΣΗ"}, {"procedureCategory", "ΜΗΝΥΜΑ"}
    }),
    #"Removed Other Columns1" = Table.SelectColumns(#"Renamed Columns", {"ΤΙΜΟΛΟΓΙΟ", "MRN", "ΗΜΕΡΟΜΗΝΙΑ", "ΩΡΑ", "ΚΑΤΑΣΤΑΣΗ", "ΜΗΝΥΜΑ"}),

    // Sort by invoice ascending, then most recent status first
    #"Sorted Rows" = Table.Sort(#"Removed Other Columns1", {{"ΤΙΜΟΛΟΓΙΟ", Order.Ascending}, {"ΗΜΕΡΟΜΗΝΙΑ", Order.Descending}, {"ΩΡΑ", Order.Descending}}),

    // Format time as 24h string
    #"24H" = Table.TransformColumns(#"Sorted Rows", {{"ΩΡΑ", each Time.ToText(_, "HH:mm:ss"), type text}}),

    // Keep only declarations that have an MRN assigned
    #"Filtered Rows" = Table.SelectRows(#"24H", each ([MRN] <> "-")),
    #"Sorted Rows1" = Table.Sort(#"Filtered Rows", {{"ΗΜΕΡΟΜΗΝΙΑ", Order.Descending}})
in
    #"Sorted Rows1"
