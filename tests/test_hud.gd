extends "res://tests/helpers/base_test.gd"
## Tests for FormatUtils number formatting.

const FU = preload("res://core/format_utils.gd")


func test_format_zero() -> void:
	assert_eq(FU.format_number(0.0), "0", "0 formats as '0'")


func test_format_small_fraction() -> void:
	assert_eq(FU.format_number(0.5), "0", "0.5 formats as '0'")


func test_format_single_digit() -> void:
	assert_eq(FU.format_number(5.0), "5", "5 formats as '5'")


func test_format_hundreds() -> void:
	assert_eq(FU.format_number(999.0), "999", "999 formats as '999'")


func test_format_thousands() -> void:
	assert_eq(FU.format_number(1234.0), "1234", "1234 stays as integer below 10K")


func test_format_ten_thousand() -> void:
	assert_eq(FU.format_number(10000.0), "10.0K", "10000 formats as '10.0K'")


func test_format_thousands_decimal() -> void:
	assert_eq(FU.format_number(45600.0), "45.6K", "45600 formats as '45.6K'")


func test_format_million() -> void:
	assert_eq(FU.format_number(1000000.0), "1.0M", "1M formats as '1.0M'")


func test_format_millions_decimal() -> void:
	assert_eq(FU.format_number(2500000.0), "2.5M", "2.5M formats as '2.5M'")


func test_format_billion() -> void:
	assert_eq(FU.format_number(1000000000.0), "1.0B", "1B formats as '1.0B'")


func test_format_billions_decimal() -> void:
	assert_eq(FU.format_number(7800000000.0), "7.8B", "7.8B formats as '7.8B'")


func test_format_negative_treated_as_zero() -> void:
	assert_eq(FU.format_number(-5.0), "0", "negative formats as '0'")
