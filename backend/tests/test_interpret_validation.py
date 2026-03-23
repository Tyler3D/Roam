from app.services.interpret_validation import validate_interpret_output


def test_validate_interpret_output_marks_generic_query_uncertain():
    result = validate_interpret_output(
        {
            "searchQuery": "restaurant",
            "invitees": [],
            "taskAssignments": None,
            "specificDatetime": None,
        }
    )
    assert result.uncertainty["requiresConfirmation"] is True
    assert result.uncertainty["flags"]["queryTooGeneric"] is True


def test_validate_interpret_output_confident_specific_query():
    result = validate_interpret_output(
        {
            "searchQuery": "rooftop bar lower east side",
            "invitees": ["Tyler"],
            "taskAssignments": "Tyler: bring drinks",
            "specificDatetime": "2026-03-25T19:00:00",
        }
    )
    assert result.uncertainty["requiresConfirmation"] is False
    assert result.uncertainty["confidence"] >= 0.8
