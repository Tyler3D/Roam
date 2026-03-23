from app.services.reelIngestion import ReelCandidate, _candidate_threshold, _place_match_score


def test_candidate_threshold_is_stricter_for_location():
    loc = ReelCandidate(kind="location", title="A", category="restaurant", confidence=0.8)
    exp = ReelCandidate(kind="experience", title="A", category="fitness", confidence=0.8)
    assert _candidate_threshold(loc) > _candidate_threshold(exp)


def test_place_match_score_prefers_name_overlap():
    candidate = ReelCandidate(
        kind="location",
        title="Joe's Pizza",
        mapsQuery="Joe's Pizza West Village",
        category="restaurant",
        confidence=0.9,
    )
    high = _place_match_score(candidate, "Joe's Pizza")
    low = _place_match_score(candidate, "Unrelated Place")
    assert high > low
