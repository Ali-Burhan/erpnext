Itemized invoice raised by Supplier.

## AI-assisted invoice extraction

Draft Purchase Invoices include an optional **Supplier Invoice File** attachment and
three extraction actions under **Get Items From**:

- **Extract from Invoice** fills the open form after confirmation; it does not save.
- **Extract and Save as Draft** extracts, fills, and saves a draft without submitting.
- **Extract and Save (Submit)** extracts, fills, saves, and submits the invoice, posting
  its accounting entries through ERPNext's normal validation and submission flow.

The save and submit actions run only when a user explicitly selects them; attaching a
file alone never creates or submits an invoice. The submit action submits immediately
without a confirmation or review step. ERPNext validations still apply, but they cannot
verify that AI-extracted values match the source invoice. Use it only when that workflow
is acceptable. Extracted tax and total values are for comparison only and do not
override ERPNext's calculations.

By default, the integration connects to `http://127.0.0.1:11434` and uses `qwen2:7b`.
Set these optional values in the site's `site_config.json` to override them:

```json
{
  "ollama_base_url": "http://127.0.0.1:11434",
  "ollama_model": "qwen2:7b",
  "tesseract_cmd": "tesseract"
}
```

Ollama keeps the model loaded for 10 minutes after a request to speed up repeated
extractions; this uses several gigabytes of system memory while the model remains loaded.
On the current CPU-bound development machine, a full extraction took about 40-50 seconds.

`pdfplumber` extracts text from PDFs. Scanned PDFs and image invoices (PNG, JPEG,
TIFF, WebP, and BMP) require Tesseract OCR installed on the Frappe server; set
`tesseract_cmd` to its executable path if it is not on `PATH`. OCR defaults to
English. The configured Ollama model receives text only; it does not inspect images.
Keep Ollama and Tesseract on a trusted host and restrict access to the site configuration.

The feature requires attached files up to 15 MB and PDFs up to 10 pages. Ollama
must be reachable from the Frappe server. Exact supplier/item matches are suggested;
unmatched values need to be resolved in the form before ERPNext will accept the invoice.
Tax and total values from the invoice are shown for comparison and are never used to
override ERPNext's tax calculations.

For foreign-currency invoices, configure an enabled currency, a supplier payable account
in that same currency, and an exchange rate for the invoice date. ERPNext blocks
submission when the party account and invoice currencies do not match.
