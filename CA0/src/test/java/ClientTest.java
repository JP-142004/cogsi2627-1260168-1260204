package com.example.bookstore.model;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class ClientTest {

    @Test
    void testClientNif() {
        // Criar um novo cliente
        Client client = new Client();
        
        // Atribuir um NIF
        client.setNif("123456789");
        
        // Verificar se o NIF foi guardado corretamente e não é nulo
        assertNotNull(client.getNif(), "O NIF não deve ser nulo");
        assertEquals("123456789", client.getNif(), "O NIF deve corresponder ao valor atribuído");
    }
}