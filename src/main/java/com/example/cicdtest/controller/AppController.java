package com.example.cicdtest.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class AppController {
  @GetMapping("/")
  public String index() {
    return "Hello, world! This is a test for CI/CD.";
  }
}
