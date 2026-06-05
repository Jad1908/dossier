from ctxforge.tokens import count_tokens


def test_empty_is_zero():
    assert count_tokens("") == 0


def test_non_empty_is_positive():
    assert count_tokens("hello world, this is some text") > 0
