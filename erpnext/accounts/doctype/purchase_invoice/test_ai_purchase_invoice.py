# Copyright (c) 2026, Frappe Technologies Pvt. Ltd. and Contributors
# License: GNU General Public License v3. See license.txt

import frappe
from frappe.tests import UnitTestCase

from erpnext.accounts.doctype.purchase_invoice.ai_purchase_invoice import (
	_get_invoice_file_content,
	_parse_model_response,
)


class TestAIPurchaseInvoiceExtraction(UnitTestCase):
	def test_invoice_file_is_read_as_bytes(self):
		class TextDecodingFile:
			def get_content(self, encodings=None):
				return "decoded PDF" if encodings is None else b"%PDF-1.4"

		self.assertEqual(_get_invoice_file_content(TextDecodingFile()), b"%PDF-1.4")

	def test_parse_invoice_extraction(self):
		data = _parse_model_response(
			'{"supplier_name":"Example Ltd","invoice_number":"INV-42",'
			'"invoice_date":"2026-03-01","due_date":null,"currency":"usd",'
			'"tax_amount":5.25,"invoice_total":55.25,"items":['
			'{"description":"Widget","quantity":2,"unit_price":25}]}'
		)

		self.assertEqual(data["supplier_name"], "Example Ltd")
		self.assertEqual(data["invoice_number"], "INV-42")
		self.assertEqual(data["invoice_date"], "2026-03-01")
		self.assertEqual(data["due_date"], "")
		self.assertEqual(data["currency"], "USD")
		self.assertEqual(data["tax_amount"], "5.25")
		self.assertEqual(data["invoice_total"], "55.25")
		self.assertEqual(data["items"][0]["quantity"], "2")
		self.assertEqual(data["items"][0]["unit_price"], "25")

	def test_reject_invalid_invoice_date(self):
		with self.assertRaises(frappe.ValidationError):
			_parse_model_response(
				'{"supplier_name":"","invoice_number":"","invoice_date":"tomorrow",'
				'"due_date":null,"currency":"","tax_amount":null,"invoice_total":null,'
				'"items":[{"description":"Widget","quantity":1,"unit_price":2}]}'
			)

	def test_missing_quantity_is_left_for_human_review(self):
		data = _parse_model_response(
			'{"supplier_name":"","invoice_number":"","invoice_date":null,"due_date":null,'
			'"currency":"","tax_amount":null,"invoice_total":null,'
			'"items":[{"description":"Widget","quantity":null,"unit_price":2}]}'
		)

		self.assertEqual(data["items"][0]["quantity"], "")

	def test_reject_invalid_invoice_lines(self):
		with self.assertRaises(frappe.ValidationError):
			_parse_model_response(
				'{"supplier_name":"","invoice_number":"","invoice_date":null,"due_date":null,'
				'"currency":"","tax_amount":null,"invoice_total":null,'
				'"items":[null]}'
			)
