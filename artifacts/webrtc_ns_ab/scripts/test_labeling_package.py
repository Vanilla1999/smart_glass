#!/usr/bin/env python3
import importlib.util, json, tempfile, unittest, wave
from pathlib import Path

ROOT=Path(__file__).parent
def load(name):
    spec=importlib.util.spec_from_file_location(name,ROOT/f"{name}.py"); mod=importlib.util.module_from_spec(spec); import sys; sys.modules[name]=mod; spec.loader.exec_module(mod); return mod
b=load("build_labeling_package"); e=load("evaluate_manual_labels"); c=load("label_segments_cli")

class Tests(unittest.TestCase):
    def event(self,start,end,text="x",variant="baseline"):
        return b.Event("r",variant,"free_text",start,end,text,())
    def test_cluster_gap_and_dedupe(self):
        clusters=b.cluster_events([self.event(0,1),self.event(1.6,2,variant="webrtc_ns_low"),self.event(3,4)])
        self.assertEqual([len(x) for x in clusters],[2,1])
    def test_clip_bounds_and_split(self):
        self.assertEqual(b.clip_ranges(.2,5.2,6),[(0.0,4.0),(4.0,5.7)])
    def test_delay_and_equal_length(self):
        pcm=b"".join(i.to_bytes(2,"little") for i in range(300))
        base=b.aligned_slice(pcm,10,110); shifted=b.aligned_slice(pcm,10,110,96)
        self.assertEqual(len(base),len(shifted)); self.assertEqual(int.from_bytes(shifted[:2],"little"),106)
    def test_strict_and_relaxed(self):
        self.assertEqual(e.classify("command","жёлтый","желтый"),"wrong_command")
        self.assertEqual(e.classify("command","жёлтый","желтый",True),"correct_command")
        self.assertEqual(e.classify("command","доступность","доступны",True),"wrong_command")
    def test_command_background(self):
        self.assertEqual(e.classify("command","вниз",""),"miss")
        self.assertEqual(e.classify("background_speech","","вниз"),"false_activation")
        self.assertEqual(e.classify("background_speech","","речь",mode="free_text"),"background_transcription")
        self.assertEqual(e.classify("silence","",""),"correct_rejection")
    def test_resume(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"labels.json"; p.write_text(json.dumps([{"segment_id":"s"}]))
            self.assertIn("s",c.load_progress(p))

if __name__=="__main__": unittest.main()
