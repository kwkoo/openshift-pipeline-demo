package com.redhat.coolstore.model;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.List;

public class Info implements Serializable {
    public String message;

    public Info(String message) {
        this.message = message;
    }
}