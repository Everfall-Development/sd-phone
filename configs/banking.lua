-- Wallet / Banking app. The phone reads the player's framework bank balance (through the
-- multi-banking adapter in bridge/server/banking.lua) and keeps its own transaction log
-- (phone_bank_transactions) as the source of truth for the list - most banking resources
-- don't expose a portable "list transactions" API, so the phone records its own entries
-- and exposes an export others can use.
return {
    TransactionLimit = 50,          -- most-recent transactions returned to the app
    MinSend          = 1,           -- smallest allowed transfer
    MaxSend          = 100000000,   -- transfer cap

    -- Allow sending to a character who is currently offline. ef_banking uses its authoritative
    -- identifier export; framework-backed systems use a guarded framework DB update. Other
    -- own-table resources (wasabi, okok, prism, tgg, fd) require the recipient to be online.
    AllowOffline     = true,

    -- Person-to-person invoicing from the Wallet's Invoices tab (business invoicing is
    -- configured in configs/services.lua and unaffected by this block).
    PersonalInvoices = {
        Enabled    = true,
        MinAmount  = 1,        -- smallest allowed invoice
        MaxAmount  = 1000000,  -- largest allowed invoice
        MaxPending = 10,       -- outstanding unpaid invoices one sender may have at once
    },
}
