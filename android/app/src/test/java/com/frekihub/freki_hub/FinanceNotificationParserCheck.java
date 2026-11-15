package com.frekihub.freki_hub;

/** Standalone checks for the production notification parser; no Android device required. */
public final class FinanceNotificationParserCheck {
    private static FinanceNotificationParser.ParsedTransaction parsed(String text) {
        FinanceNotificationParser.ParsedTransaction result = FinanceNotificationParser.parse(text);
        if (result == null) throw new AssertionError("Expected a transaction: " + text);
        return result;
    }

    private static void rejected(String text) {
        if (FinanceNotificationParser.parse(text) != null) {
            throw new AssertionError("Expected the message to be skipped: " + text);
        }
    }

    private static void expect(String text, String kind, String amount, String currency, String counterparty) {
        FinanceNotificationParser.ParsedTransaction result = parsed(text);
        if (!kind.equals(result.getKind()) || !amount.equals(result.getAmount())
                || !currency.equals(result.getCurrency()) || !counterparty.equals(result.getCounterparty())) {
            throw new AssertionError("Unexpected parse for " + text + ": " + result.getKind() + ", "
                    + result.getAmount() + " " + result.getCurrency() + ", " + result.getCounterparty());
        }
    }

    public static void main(String[] args) {
        expect("Payment successful: PHP 1,234.50 at Coffee Shop. Ref AB123456",
                "expense", "1234.50", "PHP", "Coffee Shop");
        expect("You sent 75.00 PHP to Ana", "expense", "75.00", "PHP", "Ana");
        expect("You received PHP 2,500.00 from Ana", "income", "2500.00", "PHP", "Ana");
        expect("Account credited ₱350.00", "income", "350.00", "PHP", "Not specified");
        expect("Your salary of USD 1,100.00 has been credited to your account",
                "income", "1100.00", "USD", "Not specified");
        expect("Cash-in received: KD 2.500 from Employer", "income", "2.500", "KWD", "Employer");
        expect("¥2,000 cash in", "income", "2000", "JPY", "Not specified");
        expect("₩15,000 deposited", "income", "15000", "KRW", "Not specified");
        expect("Paid $25.00 at Cafe; total $25.00", "expense", "25.00", "USD", "Cafe");
        expect("Your payment of PHP 42.00 was completed at Bookshop",
                "expense", "42.00", "PHP", "Bookshop");
        expect("Debit alert: Account deducted PHP 800.00", "expense", "800.00", "PHP", "Item not specified");
        expect("Money received: 50.00 EUR from Ana", "income", "50.00", "EUR", "Ana");

        rejected("PHP 200.00 available balance");
        rejected("Payment request: PHP 200.00");
        rejected("Payment failed: PHP 200.00 paid at Cafe");
        rejected("OTP 123456 for purchase PHP 200.00");
        rejected("PHP 1,00 debited at Cafe");
        rejected("PHP 2.500 debited at Cafe");
        rejected("PHP 100.00 received and PHP 20.00 debited");
        rejected("PHP 100.00 received from Ana and PHP 80.00 received from Bo");
        rejected("Promotional cashback received: PHP 25.00");

        // E-wallet style notifications with balance text.
        expect("You have sent PHP50.00 of GCash to JUAN DELA CRUZ 09262243647 on 02-21-2021 10:10 PM. Your new balance is PHP550.88. Ref. No. 12345678",
                "expense", "50.00", "PHP", "JUAN DELA CRUZ 09262243647");
        expect("You received PHP 1,000.00 from ANA. Your new balance is PHP 2,500.00.",
                "income", "1000.00", "PHP", "ANA");
        expect("Money sent successfully. You sent P250.00 to MARIA. New balance: P1,750.00",
                "expense", "250.00", "PHP", "MARIA");
        expect("Transfer successful! You received P500 from PEDRO. Available balance P1,000.00",
                "income", "500", "PHP", "PEDRO");
        expect("Maribank debit transaction of PHP 150.00 at Coffee Shop",
                "expense", "150.00", "PHP", "Coffee Shop");
        expect("MariBank debit transaction of PHP1,234.56",
                "expense", "1234.56", "PHP", "Item not specified");
        System.out.println("27 finance notification parser checks passed");
    }
}
