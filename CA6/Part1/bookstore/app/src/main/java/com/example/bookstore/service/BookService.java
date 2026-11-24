package com.example.bookstore.service;

import com.example.bookstore.model.Book;
import com.example.bookstore.repository.BookRepository;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.Gauge;
import io.micrometer.core.instrument.MeterRegistry;
import io.micrometer.core.instrument.Timer;
import org.springframework.stereotype.Service;

import java.util.List;
import java.util.Optional;

/**
 * Book operations, instrumented with custom Micrometer metrics.
 */
@Service
public class BookService {

    private final BookRepository repo;
    private final Counter booksAdded;
    private final Timer listTimer;

    public BookService(BookRepository repo, MeterRegistry registry) {
        this.repo = repo;
        this.booksAdded = Counter.builder("bookstore.books.added")
                .description("Number of books created through the API")
                .register(registry);
        this.listTimer = Timer.builder("bookstore.books.list")
                .description("Time taken to list all books")
                .publishPercentileHistogram()
                .register(registry);
        // Lido a cada scrape, por isso reflete também inserções feitas fora da API
        Gauge.builder("bookstore.books.stored", repo, BookRepository::count)
                .description("Total number of books in the database")
                .register(registry);
    }

    public List<Book> findAll() {
        return listTimer.record(() -> repo.findAll());
    }

    public Optional<Book> findById(Long id) {
        return repo.findById(id);
    }

    public Book create(Book book) {
        Book saved = repo.save(book);
        booksAdded.increment();
        return saved;
    }
}
