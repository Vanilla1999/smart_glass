package com.xcheng.uac4client;

import com.xcheng.uac4client.IUac4AppCallback;

interface IUac4AppService {
    int initUac4(in IUac4AppCallback callback);
    int startUac4Mic();
    int stopUac4Mic();
    int deinitUac4();
}
