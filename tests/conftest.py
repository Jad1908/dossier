from pathlib import Path

import pytest

FIXTURES = Path(__file__).parent / "fixtures"


@pytest.fixture
def sample_repo() -> Path:
    return FIXTURES / "sample_repo"
