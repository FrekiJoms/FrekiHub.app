package com.frekihub.freki_hub;

import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Conservative local parser for selected apps' transaction notifications. */
public final class FinanceNotificationParser {
    private static final String CURRENCY = "(?:US\\$|PHP|USD|EUR|GBP|JPY|KRW|KWD|KD|₱|\\$|€|£|¥|₩)";
    private static final String NUMBER = "(?:[0-9]{1,3}(?:,[0-9]{3})+|[0-9]+)(?:\\.[0-9]{1,3})?";
    private static final Pattern PREFIX_AMOUNT = Pattern.compile(
            "(?i)(?<![\\p{L}\\p{N}])(" + CURRENCY + ")\\s*[:#-]?\\s*(" + NUMBER + ")(?![0-9.,])");
    private static final Pattern SUFFIX_AMOUNT = Pattern.compile(
            "(?i)(?<![0-9.,])(" + NUMBER + ")\\s*(" + CURRENCY + ")(?![\\p{L}\\p{N}])");
    private static final Pattern REJECT = Pattern.compile(
            "(?i)\\b(?:otp|one[\\s-]?time password|verification code|failed|failure|declined|rejected|unsuccessful|pending|processing|reversed|cancelled|canceled|payment request|request to pay|promo(?:tional)?|promotion(?:al)?|limited time offer)\\b");
    private static final Pattern INCOMING = Pattern.compile(
            "(?i)\\b(?:received|credited|credit alert|deposit(?:ed)?|salary|cash[\\s-]?in|cashback|refund(?:ed)?|reimbursed|reimbursement|payout|remittance|top[\\s-]?up|incoming transfer|money received|funds received|account funded|funds added|paid you|paid into your account|paid to your account|transfer from|credit to your account)\\b");
    private static final Pattern HARD_OUTGOING = Pattern.compile(
            "(?i)\\b(?:debited|deducted|debit alert|purchased|purchase(?: successful| of)|withdrawn|withdrawal|cash[\\s-]?out|sent to|transferred to|transfer to|payment to|charged at|spent|bought|paid at|paid to (?!your account))\\b");
    private static final Pattern OUTGOING = Pattern.compile(
            "(?i)\\b(?:paid|purchased|purchase(?: successful| of)|payment successful|successful payment|debited|deducted|sent|spent|charged|withdrawn|withdrawal|cash[\\s-]?out|transferred to|transfer to|payment to|bought)\\b");
    private static final Pattern COMPLETED_PAYMENT = Pattern.compile(
            "(?i)\\bpayment\\b.{0,60}\\b(?:successful|succeeded|completed|confirmed|processed)\\b|\\b(?:successful|succeeded|completed|confirmed|processed)\\b.{0,60}\\bpayment\\b");
    private static final Pattern INCOME_SOURCE = Pattern.compile(
            "(?i)\\b(?:from|sender)\\s+([^\\n,.;]{2,80})");
    private static final Pattern EXPENSE_MERCHANT = Pattern.compile(
            "(?i)\\b(?:at|to)\\s+([^\\n,.;]{2,80})");

    private FinanceNotificationParser() {}

    public static final class ParsedTransaction {
        private final String kind;
        private final String amount;
        private final String currency;
        private final String counterparty;

        private ParsedTransaction(String kind, String amount, String currency, String counterparty) {
            this.kind = kind;
            this.amount = amount;
            this.currency = currency;
            this.counterparty = counterparty;
        }

        public String getKind() { return kind; }
        public String getAmount() { return amount; }
        public String getCurrency() { return currency; }
        public String getCounterparty() { return counterparty; }
    }

    /** Returns null unless the message contains a clear direction and one amount. */
    public static ParsedTransaction parse(String rawText) {
        if (rawText == null || rawText.isBlank()) return null;
        String text = rawText.replace('\u00a0', ' ').replace('\u202f', ' ');
        if (REJECT.matcher(text).find()) return null;

        boolean incoming = INCOMING.matcher(text).find();
        boolean hardOutgoing = HARD_OUTGOING.matcher(text).find();
        boolean outgoing = OUTGOING.matcher(text).find() || COMPLETED_PAYMENT.matcher(text).find();
        if (incoming && hardOutgoing) return null; // Conflicting direction; do not guess.
        if (!incoming && !outgoing) return null;
        String kind = incoming ? "income" : "expense";

        Map<String, String> amounts = new LinkedHashMap<>();
        collectAmounts(PREFIX_AMOUNT.matcher(text), true, amounts);
        collectAmounts(SUFFIX_AMOUNT.matcher(text), false, amounts);
        if (amounts.size() != 1) return null;
        Map.Entry<String, String> amount = amounts.entrySet().iterator().next();
        String[] parts = amount.getKey().split(":", 2);
        String currency = parts[0];
        String value = amount.getValue();
        int decimal = value.indexOf('.');
        if (decimal >= 0 && value.length() - decimal - 1 > fractionDigits(currency)) return null;
        try {
            if (new java.math.BigDecimal(value).signum() <= 0) return null;
        } catch (NumberFormatException invalid) {
            return null;
        }

        String counterparty = findCounterparty(
                kind.equals("income") ? INCOME_SOURCE : EXPENSE_MERCHANT,
                text,
                kind.equals("income") ? "Not specified" : "Item not specified");
        return new ParsedTransaction(kind, value, currency, counterparty);
    }

    private static void collectAmounts(Matcher matcher, boolean currencyFirst, Map<String, String> amounts) {
        while (matcher.find()) {
            String token = matcher.group(currencyFirst ? 1 : 2);
            String value = matcher.group(currencyFirst ? 2 : 1).replace(",", "");
            String currency = currency(token);
            if (currency != null) amounts.put(currency + ":" + value, value);
        }
    }

    private static String currency(String token) {
        return switch (token.toUpperCase(Locale.ROOT)) {
            case "PHP", "₱" -> "PHP";
            case "USD", "US$", "$" -> "USD";
            case "EUR", "€" -> "EUR";
            case "GBP", "£" -> "GBP";
            case "JPY", "¥" -> "JPY";
            case "KRW", "₩" -> "KRW";
            case "KWD", "KD" -> "KWD";
            default -> null;
        };
    }

    private static int fractionDigits(String currency) {
        return switch (currency) {
            case "JPY", "KRW" -> 0;
            case "KWD" -> 3;
            default -> 2;
        };
    }

    private static String findCounterparty(Pattern pattern, String text, String fallback) {
        Matcher matcher = pattern.matcher(text);
        if (!matcher.find()) return fallback;
        String value = matcher.group(1).trim().replaceAll("\\s+", " ");
        value = value.replaceAll("(?i)\\s+(?:reference|ref|transaction|id)\\b.*$", "").trim();
        return value.isEmpty() ? fallback : value;
    }
}
