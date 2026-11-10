// florv: the PC command line tool.
//
//   florv iss prog.elf [--max-steps N] [--trace out.csv]
//
// Runs an RV32I ELF in the instruction-set simulator until it halts, traps or reaches
// the step limit, and optionally writes the CSV retire trace of docs/trace-format.md.

#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "elf_image.hpp"
#include "iss.hpp"
#include "memory.hpp"
#include "trace_csv.hpp"
#include "version.hpp"

namespace {

// What the process returns. Scripts and ctest read these, not the printed text.
enum ExitCode : int {
    kExitPass = 0,     // halted with tohost equal to 1
    kExitFail = 1,     // halted another way: another tohost value, ecall or ebreak
    kExitStopped = 2,  // step limit reached, or a trap
    kExitBadElf = 3,   // file unreadable, not a valid RV32 ELF, or it does not fit the RAM
    kExitUsage = 4,    // wrong command line, or the trace file cannot be written
};

constexpr std::uint64_t kDefaultMaxSteps = 1000000;

void printUsage(std::FILE* out) {
    std::fprintf(out,
                 "usage: florv iss <prog.elf> [--max-steps N] [--trace out.csv]\n"
                 "       florv --version\n"
                 "\n"
                 "  --max-steps N   stop after N instructions (default %llu)\n"
                 "  --trace FILE    write the CSV retire trace to FILE\n"
                 "\n"
                 "exit codes: 0 halted with tohost 1, 1 halted otherwise,\n"
                 "            2 step limit or trap, 3 bad ELF, 4 bad command line\n",
                 static_cast<unsigned long long>(kDefaultMaxSteps));
}

// Returns false when the file cannot be opened or read.
bool readFile(const std::string& path, std::vector<std::uint8_t>& bytes) {
    std::FILE* file = std::fopen(path.c_str(), "rb");
    if (file == nullptr) {
        return false;
    }
    std::uint8_t chunk[4096];
    std::size_t got = 0;
    while ((got = std::fread(chunk, 1, sizeof(chunk), file)) > 0) {
        bytes.insert(bytes.end(), chunk, chunk + got);
    }
    const bool ok = std::ferror(file) == 0;
    std::fclose(file);
    return ok;
}

// A whole decimal number and nothing else.
bool parseCount(const char* text, std::uint64_t& value) {
    if (text[0] < '0' || text[0] > '9') {
        return false;
    }
    errno = 0;
    char* end = nullptr;
    const unsigned long long parsed = std::strtoull(text, &end, 10);
    if (errno != 0 || *end != '\0') {
        return false;
    }
    value = parsed;
    return true;
}

struct IssOptions {
    std::string elfPath;
    std::string tracePath;  // empty: no trace
    std::uint64_t maxSteps = kDefaultMaxSteps;
};

// args are the words after "iss".
bool parseIssOptions(int count, char** args, IssOptions& options) {
    for (int i = 0; i < count; ++i) {
        const std::string arg = args[i];
        if (arg == "--max-steps") {
            if (i + 1 >= count || !parseCount(args[i + 1], options.maxSteps)) {
                std::fprintf(stderr, "florv: --max-steps needs a number\n");
                return false;
            }
            ++i;
        } else if (arg == "--trace") {
            if (i + 1 >= count) {
                std::fprintf(stderr, "florv: --trace needs a file name\n");
                return false;
            }
            options.tracePath = args[i + 1];
            ++i;
        } else if (!arg.empty() && arg[0] == '-') {
            std::fprintf(stderr, "florv: unknown option %s\n", arg.c_str());
            return false;
        } else if (options.elfPath.empty()) {
            options.elfPath = arg;
        } else {
            std::fprintf(stderr, "florv: more than one ELF file given\n");
            return false;
        }
    }
    if (options.elfPath.empty()) {
        std::fprintf(stderr, "florv: no ELF file given\n");
        return false;
    }
    return true;
}

int runIss(const IssOptions& options) {
    std::vector<std::uint8_t> file;
    if (!readFile(options.elfPath, file)) {
        std::fprintf(stderr, "florv: cannot read %s\n", options.elfPath.c_str());
        return kExitBadElf;
    }

    const auto image = florv::ElfImage::parse(florv::ByteView{file.data(), file.size()});
    if (!image) {
        std::fprintf(stderr, "florv: %s is not a 32-bit RISC-V executable\n",
                     options.elfPath.c_str());
        return kExitBadElf;
    }

    static florv::Memory ram;  // 64 KiB, so not on the stack
    if (ram.loadSegments(*image) != florv::MemStatus::Ok) {
        std::fprintf(stderr, "florv: %s does not fit the RAM at %08x, %u bytes\n",
                     options.elfPath.c_str(), static_cast<unsigned>(ram.base()),
                     static_cast<unsigned>(ram.size()));
        return kExitBadElf;
    }

    florv::Iss iss(ram);
    iss.reset(image->entry());
    if (const auto tohost = image->findSymbol("tohost")) {
        iss.setTohost(*tohost);
    }

    // "wb", not "w": the trace has line feeds only, on Windows too.
    std::FILE* trace = nullptr;
    if (!options.tracePath.empty()) {
        trace = std::fopen(options.tracePath.c_str(), "wb");
        if (trace == nullptr) {
            std::fprintf(stderr, "florv: cannot write %s\n", options.tracePath.c_str());
            return kExitUsage;
        }
        std::fprintf(trace, "%s\n", florv::kTraceCsvHeader);
    }

    florv::StepStatus status = florv::StepStatus::Ok;
    florv::RetireRecord last;
    while (status == florv::StepStatus::Ok && iss.retired() < options.maxSteps) {
        const florv::StepResult result = iss.step();
        status = result.status;
        last = result.record;
        if (trace != nullptr && status != florv::StepStatus::Trap) {
            char line[florv::kTraceCsvLineSize];
            florv::toCsv(result.record, line, sizeof(line));
            std::fprintf(trace, "%s\n", line);
        }
    }

    if (trace != nullptr) {
        const bool writeFailed = std::ferror(trace) != 0;
        if (std::fclose(trace) != 0 || writeFailed) {
            std::fprintf(stderr, "florv: error writing %s\n", options.tracePath.c_str());
            return kExitUsage;
        }
    }

    const char* outcome = "step limit";
    int code = kExitStopped;
    if (status == florv::StepStatus::Halted) {
        outcome = "halted";
        code = iss.tohostValue() == 1 ? kExitPass : kExitFail;
    } else if (status == florv::StepStatus::Trap) {
        outcome = "trap";
    }

    std::printf("status:  %s\n", outcome);
    std::printf("tohost:  %u\n", static_cast<unsigned>(iss.tohostValue()));
    std::printf("retired: %u\n", static_cast<unsigned>(iss.retired()));
    if (status == florv::StepStatus::Trap) {
        std::printf("trap at: pc=%08x insn=%08x\n", static_cast<unsigned>(last.pc),
                    static_cast<unsigned>(last.insn));
    }
    return code;
}

}  // namespace

int main(int argc, char** argv) {
    if (argc >= 2 && std::strcmp(argv[1], "--version") == 0) {
        std::printf("florv %s\n", florv::version());
        return kExitPass;
    }
    if (argc >= 2 && (std::strcmp(argv[1], "--help") == 0 || std::strcmp(argv[1], "-h") == 0)) {
        printUsage(stdout);
        return kExitPass;
    }
    if (argc >= 2 && std::strcmp(argv[1], "iss") == 0) {
        IssOptions options;
        if (!parseIssOptions(argc - 2, argv + 2, options)) {
            printUsage(stderr);
            return kExitUsage;
        }
        return runIss(options);
    }
    printUsage(stderr);
    return kExitUsage;
}
