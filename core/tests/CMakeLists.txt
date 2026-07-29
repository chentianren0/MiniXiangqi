# The one shared C++ test runner.
#
# It links the core static library and runs without any frontend, which is what
# docs/architecture.md requires of it on every development platform. It has no
# third-party dependency and fetches nothing, so it configures and builds the
# same way on a machine that has only a compiler and CMake.

add_executable(mxq_core_tests
  main.cpp
  mxq_fixture.cpp
  mxq_json.cpp
  mxq_rules_facade.cpp
)

target_link_libraries(mxq_core_tests PRIVATE mxq::core mxq_warnings)

# fixtures/ lives at the repository root rather than under core/: it is the
# independent authority the core is validated against, not an implementation
# detail of the core it validates. The path below is only the default; the
# runner also accepts --fixtures and $MXQ_FIXTURES_DIR, which is how CI points
# it at a checkout in another location.
target_compile_definitions(mxq_core_tests PRIVATE
  MXQ_FIXTURES_DIR_DEFAULT="${MXQ_REPO_ROOT}/fixtures/rules"
  MXQ_TEST_RULES_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_RULES_FACADE}>,$<BOOL:${MXQ_RULES_FACADE_IMPLEMENTED}>>,1,0>
  # The core loads the bundled variant configuration from its asset directory.
  # The runner's store directory is a scratch path, so the two are not the same
  # place and the asset directory has to be told to it explicitly.
  MXQ_ASSETS_DIR_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/../assets"
)

add_test(NAME rules_fixtures
         COMMAND mxq_core_tests
                 --junit "${CMAKE_CURRENT_BINARY_DIR}/rules-fixtures.xml")
set_tests_properties(rules_fixtures PROPERTIES
  LABELS "rules;fixtures"
)

# The store-foundation runner: the SQLite-backed store mxq_core_init opens,
# asserted against scratch databases, plus the deterministic-identity seam.
# It links the vendored SQLite directly so schema assertions query the closed
# database rather than trust the DDL, and it includes the core's internal
# headers on purpose — the identity provider has no public accessor, and the
# white-box read is the test's whole point. Both runs need no engine; with the
# engine compiled in, mxq_core_init also loads the variant configuration, so
# the assets default is supplied the same way as above.

add_executable(mxq_store_tests
  mxq_store_tests.cpp
)
target_link_libraries(mxq_store_tests PRIVATE mxq::core mxq::sqlite mxq_warnings)
target_include_directories(mxq_store_tests PRIVATE
  "${CMAKE_CURRENT_SOURCE_DIR}/../src"
)
target_compile_definitions(mxq_store_tests PRIVATE
  MXQ_ASSETS_DIR_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/../assets"
)

add_test(NAME store_foundation COMMAND mxq_store_tests)
set_tests_properties(store_foundation PROPERTIES
  LABELS "store"
)

# The archive-codec runner: the golden and rejection corpora in
# fixtures/archive/, walked through the public C surface only. It shares the
# fixture runner's JSON reader for the expectation sidecars — that reader is
# fixture-side code and is deliberately not what the codec parses archives
# with; the core carries its own reader for that.
#
# It behaves in each configuration exactly as rules_fixtures does. With the
# engine, mxq_archive_validate exists and every expectation is evaluated;
# without it, validate is absent from the library and the runner reports its
# expectations as NOT IMPLEMENTED rather than referencing a symbol that would
# fail to link.

add_executable(mxq_archive_tests
  mxq_archive_tests.cpp
  mxq_json.cpp
)
target_link_libraries(mxq_archive_tests PRIVATE mxq::core mxq_warnings)
target_compile_definitions(mxq_archive_tests PRIVATE
  MXQ_ARCHIVE_FIXTURES_DIR_DEFAULT="${MXQ_REPO_ROOT}/fixtures/archive"
  MXQ_TEST_RULES_FACADE=$<IF:$<AND:$<BOOL:${MXQ_ENABLE_RULES_FACADE}>,$<BOOL:${MXQ_RULES_FACADE_IMPLEMENTED}>>,1,0>
  MXQ_ASSETS_DIR_DEFAULT="${CMAKE_CURRENT_SOURCE_DIR}/../assets"
)

add_test(NAME archive_fixtures COMMAND mxq_archive_tests)
set_tests_properties(archive_fixtures PROPERTIES
  LABELS "archive;fixtures"
)
