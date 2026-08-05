package com.xcheng.uac4client;

oneway interface IUac4AppCallback {
    void onAudioData(in byte[] data);
}
