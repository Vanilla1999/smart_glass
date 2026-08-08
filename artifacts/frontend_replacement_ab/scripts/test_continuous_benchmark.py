#!/usr/bin/env python3
"""Unit tests for deterministic continuous benchmark helpers."""

from continuous_common import (
    Region, deduplicate_hard_negatives, duplicate_action_count, evaluation_region,
    false_actions_per_minute, first_expected_time, pairwise_delta, stable_expected_time,
    subtract_regions,
)
from build_continuous_frontend_matrix import align_raw_to_ssp
from score_continuous_benchmark import build_occurrence_owners, event_owner


def event(time, kind="partial", partial="", text=""):
    return {"timestamp_end_s":time,"event_type":kind,"partial":partial,"text":text}


def main() -> None:
    assert evaluation_region(0.1,1.0,2.0)==Region(0.0,2.0)
    assert subtract_regions(10,[Region(1,2),Region(1.5,3),Region(8,9)])==[Region(0,1),Region(3,8),Region(9,10)]
    assert align_raw_to_ssp(b"\x01\x00\x02\x00",3,1)==b"\x00\x00\x01\x00\x02\x00"
    events=[event(1.0,partial="вверх"),event(1.08,partial="вверх"),event(1.16,partial="вверх")]
    assert first_expected_time(events,"вверх",0.8)==199.99999999999994
    assert round(stable_expected_time(events,"вверх",0.8))==350
    assert stable_expected_time([event(1,partial="вверх"),event(1.08,partial="вниз")],"вверх",0.8) is None
    assert duplicate_action_count([1.0,1.2,4.0],Region(.5,2))==1
    hard=deduplicate_hard_negatives([("a",2,"вверх","r"),("b",3,"вниз","r"),("a",10,"вверх","r")])
    assert len(hard)==2 and hard[0]["frontends"]=={"a","b"}
    assert false_actions_per_minute(2,120)==1
    legacy={"detected":"false","wrong_actionable_partial":"0","stable_partial_latency_ms":""}
    candidate={"detected":"true","wrong_actionable_partial":"0","stable_partial_latency_ms":""}
    assert pairwise_delta(legacy,candidate)=="fixed_legacy_miss"
    labels=[{"recording":"r","utterance_id":"a","expected_text":"вниз","start_s_ssp":"1","end_s_ssp":"1.4"},
            {"recording":"r","utterance_id":"b","expected_text":"вниз","start_s_ssp":"2","end_s_ssp":"2.4"}]
    assert event_owner({"recording":"r","timestamp_end_s":2.0},"вниз",labels,{"r":3})=="b"
    occurrence_events=[{"recording":"r","frontend":"f","mode":"m","utterance_id":1,
                        "timestamp_end_s":1.1,"partial":"вниз","text":""},
                       {"recording":"r","frontend":"f","mode":"m","utterance_id":2,
                        "timestamp_end_s":2.1,"partial":"вниз","text":""}]
    owners=build_occurrence_owners(occurrence_events,labels,{"r":3})
    assert owners[("r","f","m",1,"вниз")]=="a" and owners[("r","f","m",2,"вниз")]=="b"
    print("CONTINUOUS_BENCHMARK_TEST_OK")


if __name__=="__main__": main()
