package org.example;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertTrue;

class AppTest {

    @Test
    void greetingContainsApplicationName() {
        App app = new App();

        assertTrue(
            app.getGreeting().contains("Multi-User Chat Application"),
            "The greeting should contain the application name"
        );
    }
}