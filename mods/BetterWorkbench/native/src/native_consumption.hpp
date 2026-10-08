#pragma once
// Synchronous completion context. The native atomic add/remove transaction
// retains its product, permissions, policy and event handling unchanged.
struct NativeDebit { std::array<uint8_t,16> container; int32_t slot,quantity; };
static_assert(sizeof(NativeDebit)==24);
struct CompletionContext {
    void* model{};
    std::shared_ptr<ActiveJob> job;
    std::size_t index{};
    OwnedNativeArray debits;
    std::vector<better_workbench::InputDebit> expected;
    std::vector<int32_t> before;
    void* container{};
    bool called{};
    uint8_t status{255};
};
thread_local CompletionContext* completing_job{};
uint64_t transaction_trampoline{};
std::atomic<unsigned> debit_logs{},debit_errors{};
using TransactionFunction=uint8_t (*)(void*,void*,BorrowedArray*,void*,void*,void*);
void prepare_completion(CompletionContext& context) {
    context.index=job_index(context.job,context.model);
    const auto& unit=job_unit(context.job,context.model);
    context.expected=better_workbench::input_debits(context.job->schedule.total,unit);
    context.container=ensure_dynamic_capacity(context.model,context.job->schedule.total.size());
    const auto container_id=field<std::array<uint8_t,16>>(context.container,0x38);
    using GetSlot=void* (*)(void*,int32_t);
    std::vector<NativeDebit> operations;
    for(const auto& debit:context.expected) {
        auto* slot=reinterpret_cast<GetSlot>(game_base()+0x2fa9650)(context.container,debit.slot);
        if(!slot || field<uint64_t>(slot,0x12c)!=name_bits(debit.item.c_str())
            || field<int32_t>(slot,0x118)!=debit.slot
            || field<std::array<uint8_t,16>>(slot,0x11c)!=container_id)
            throw std::runtime_error("native debit slot identity mismatch");
        const auto count=field<int32_t>(slot,0x154);
        if(count<debit.quantity) throw std::runtime_error("native debit slot lacks material");
        operations.push_back({container_id,debit.slot,debit.quantity});
        context.before.push_back(count);
    }
    if(!operations.empty()) append_native_array(&context.debits.value,operations);
}
uint8_t job_transaction(void* world,void* product,BorrowedArray* removals,void* policy,void* arg5,void* arg6) {
    const auto original=reinterpret_cast<TransactionFunction>(transaction_trampoline);
    if(!completing_job || reinterpret_cast<uintptr_t>(_ReturnAddress())!=game_base()+0x30135d6)
        return original(world,product,removals,policy,arg5,arg6);
    auto& context=*completing_job;
    // The original's five-slot collection is replaced as one operation. Never
    // perform a second removal after the native transaction has produced output.
    context.called=true;
    context.status=original(world,product,&context.debits.value,policy,arg5,arg6);
    return context.status;
}
void audit_completion(const CompletionContext& context) {
    const bool log=debit_logs.fetch_add(1)<24;
    bool exact=context.called;
    auto* slots=field<void*>(context.container,0x70);
    for(std::size_t index=0;index<context.expected.size();++index) {
        const auto& debit=context.expected[index];
        auto* slot=field<void*>(slots,debit.slot*8);
        const auto after=slot?field<int32_t>(slot,0x154):-1;
        const auto spent=context.before[index]-after;
        if(spent!=debit.quantity) exact=false;
        if(log) Output::send(STR("[BetterWorkbenchNative] DEBIT item={} slot={} required={} before={} after={} spent={}\n"),
            debit.item,debit.slot,debit.quantity,context.before[index],after,spent);
    }
    if(log || !exact) Output::send(STR("[BetterWorkbenchNative] DEBIT_RESULT root={} unit={} transaction_called={} status={} exact={}\n"),
        context.job->root,context.index,context.called,context.status,exact);
}
